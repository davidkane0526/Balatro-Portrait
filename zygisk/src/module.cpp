// Balatro Portrait — Zygisk module.
// Swaps conf.lua for the embedded Lua, which builds the portrait game into the
// save folder, and loads the game's chunks from there (luaL_loadbuffer swap);
// forces portrait orientation (Android_JNI_SetOrientation -> JNI
// setRequestedOrientation(1)); and runs Lovely on the chunks when the app's
// Mods folder has mods in it.
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <dirent.h>
#include <pthread.h>
#include <unistd.h>
#include <dlfcn.h>
#include <jni.h>
#include <android/log.h>

#include "zygisk.hpp"
#include "shadowhook.h"
#include "xdl.h"
#include "assets_gen.h"

// Provided by our shadowhook patch (sh_linker.c): absolute path to load
// libshadowhook_nothing.so from, instead of the default linker search path.
extern "C" char sh_linker_nothing_override_path[512];

#define TARGET_PKG "com.playstack.balatro.android"
#define LOG_TAG "BalatroPortrait"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

using zygisk::Api;
using zygisk::AppSpecializeArgs;

static JavaVM *g_vm = nullptr;

// ---- Lovely (crates/liblovely, linked in statically) ----
// The field order is lovely-core's LuaLib at the commit fetch_deps.ps1 pins.
typedef int (*loadbuffer_t)(void *, const char *, size_t, const char *);
typedef int (*loadbufferx_t)(void *, const char *, size_t, const char *, const char *);

static const char *const kLuaSymbols[] = {
    "lua_call", "lua_pcall", "lua_getfield", "lua_setfield", "lua_gettop", "lua_settop",
    "lua_pushvalue", "lua_pushcclosure", "lua_tolstring", "lua_type", "lua_pushstring",
    "lua_pushnumber", "lua_pushboolean", "lua_settable", "lua_createtable", "lua_error",
    "luaL_register", "luaL_checklstring",
};
struct LuaLib { void *fn[sizeof(kLuaSymbols) / sizeof(kLuaSymbols[0])]; };

extern "C" void lovely_init(loadbufferx_t recall, LuaLib lua);
extern "C" int lovely_apply_patches(void *L, const char *buff, size_t sz, const char *name, const char *mode);

// ---- luaL_loadbuffer / luaL_loadbufferx hooks ----
static loadbuffer_t orig_loadbuffer = nullptr;
static loadbufferx_t orig_loadbufferx = nullptr;

static int load_original(void *L, const char *buff, size_t sz, const char *name, const char *mode) {
  if (orig_loadbufferx) return orig_loadbufferx(L, buff, sz, name, mode);
  return orig_loadbuffer(L, buff, sz, name);
}

// LOVE names its save folder per build, so both names are looked at.
static char g_app_data[256];
static const char *const kSaveNames[] = {"ASET", "game"};

static bool has_mods(const char *dir) {
  DIR *d = opendir(dir);
  if (!d) return false;
  bool found = false;
  while (dirent *e = readdir(d)) {
    // Lovely's own folder and Steamodded's config outlive the mods.
    if (e->d_name[0] != '.' && strcmp(e->d_name, "lovely") != 0 && strcmp(e->d_name, "config") != 0) {
      found = true;
      break;
    }
  }
  closedir(d);
  return found;
}

// Lovely only starts when there is a mod to load: with an empty Mods folder
// the module behaves as if Lovely were not in it. A missing Lua symbol costs
// the mods, never the game.
static bool lovely_ready() {
  static int state = 0;  // 0 not checked, 1 running, 2 off
  if (state) return state == 1;
  state = 2;

  char dir[320] = "";
  for (const char *save : kSaveNames) {
    char candidate[320];
    snprintf(candidate, sizeof candidate, "%s/files/save/%s/Mods", g_app_data, save);
    if (has_mods(candidate)) { strcpy(dir, candidate); break; }
  }
  if (!dir[0]) return false;

  void *love = xdl_open("liblove.so", XDL_DEFAULT);
  if (!love) { LOGE("mods: liblove.so not found"); return false; }
  LuaLib lua;
  bool complete = true;
  for (size_t i = 0; i < sizeof(kLuaSymbols) / sizeof(kLuaSymbols[0]); i++) {
    lua.fn[i] = xdl_sym(love, kLuaSymbols[i], nullptr);
    if (!lua.fn[i]) lua.fn[i] = xdl_dsym(love, kLuaSymbols[i], nullptr);
    if (!lua.fn[i]) { LOGE("mods: %s not found, mods stay off", kLuaSymbols[i]); complete = false; }
  }
  xdl_close(love);
  if (!complete) return false;

  setenv("LOVELY_MOD_DIR", dir, 1);
  lovely_init(load_original, lua);
  state = 1;
  LOGI("mods: Lovely running, mod folder %s", dir);
  return true;
}

// A chunk patcher.lua built, or nullptr: then the game's own one loads. Caller frees.
static char *read_built_chunk(const char *rel, size_t *size) {
  if (strstr(rel, "..")) return nullptr;
  for (const char *save : kSaveNames) {
    char path[640];
    snprintf(path, sizeof path, "%s/files/save/%s/portrait_game/%s", g_app_data, save, rel);
    FILE *f = fopen(path, "rb");
    if (!f) continue;
    char *data = nullptr;
    long len = fseek(f, 0, SEEK_END) == 0 ? ftell(f) : -1;
    if (len > 0 && fseek(f, 0, SEEK_SET) == 0 && (data = (char *)malloc(len))) {
      if (fread(data, 1, len, f) == (size_t)len) {
        *size = len;
      } else {
        free(data);
        data = nullptr;
      }
    }
    fclose(f);
    if (data) return data;
  }
  return nullptr;
}

// Both entry points land here and go straight to the original loader, so a
// chunk is never swapped or patched twice. The swap comes first: Lovely patches
// the portrait source, as it does in the APK.
static int load_chunk(void *L, const char *buff, size_t sz, const char *name, const char *mode) {
  char *built = nullptr;
  if (name && name[0] == '@') {
    const char *rel = name + 1;
    bool embedded = false;
    for (int i = 0; i < kAssetCount; i++) {
      if (strcmp(rel, kAssets[i].name) == 0) {
        buff = (const char *)kAssets[i].data;
        sz = kAssets[i].len;
        embedded = true;
        break;
      }
    }
    if (!embedded && (built = read_built_chunk(rel, &sz))) buff = built;
  }
  int result = name && lovely_ready() ? lovely_apply_patches(L, buff, sz, name, mode)
                                      : load_original(L, buff, sz, name, mode);
  free(built);
  return result;
}

static int my_loadbuffer(void *L, const char *buff, size_t sz, const char *name) {
  return load_chunk(L, buff, sz, name, nullptr);
}

static int my_loadbufferx(void *L, const char *buff, size_t sz, const char *name, const char *mode) {
  return load_chunk(L, buff, sz, name, mode);
}

// ---- Android_JNI_SetOrientation hook (force portrait) ----
typedef void (*setorient_t)(int, int, int, const char *);
static setorient_t orig_setorient = nullptr;
static jclass g_sdlactivity_cls = nullptr;  // global ref, cached
static jfieldID g_singleton_fid = nullptr;
static jmethodID g_setreqorient_mid = nullptr;

// ---- Keyboard watch ----
// Android tells an app nothing when its keyboard closes from the keyboard's own
// chevron, and SDL only catches the back key. The APK carries this as
// src/smali/org/libsdl/app/PortraitKeyboardWatch.smali; the official app's Java
// is left alone, so here it runs from a thread of ours. Once the keyboard has been
// seen and gone it reports what the back key reports, and SDL stops text input
// (#4). Needs Android 11's WindowInsets: older versions go without.
static void *keyboard_watch(void *) {
  JNIEnv *env = nullptr;
  if (g_vm->AttachCurrentThreadAsDaemon(&env, nullptr) != JNI_OK) return nullptr;

  jmethodID shown = env->GetStaticMethodID(g_sdlactivity_cls, "isScreenKeyboardShown", "()Z");
  jmethodID lost = env->GetStaticMethodID(g_sdlactivity_cls, "onNativeKeyboardFocusLost", "()V");
  jclass activity = env->FindClass("android/app/Activity");
  jclass window = env->FindClass("android/view/Window");
  jclass view = env->FindClass("android/view/View");
  jclass insets = env->FindClass("android/view/WindowInsets");
  jclass type = env->FindClass("android/view/WindowInsets$Type");
  if (env->ExceptionCheck()) env->ExceptionClear();
  if (!shown || !lost || !activity || !window || !view || !insets || !type) {
    LOGI("keyboard watch: not on this Android");
    g_vm->DetachCurrentThread();
    return nullptr;
  }
  jmethodID get_window = env->GetMethodID(activity, "getWindow", "()Landroid/view/Window;");
  jmethodID get_decor = env->GetMethodID(window, "getDecorView", "()Landroid/view/View;");
  jmethodID get_insets = env->GetMethodID(view, "getRootWindowInsets", "()Landroid/view/WindowInsets;");
  jmethodID is_visible = env->GetMethodID(insets, "isVisible", "(I)Z");
  jmethodID ime = env->GetStaticMethodID(type, "ime", "()I");
  if (env->ExceptionCheck()) env->ExceptionClear();
  if (!get_window || !get_decor || !get_insets || !is_visible || !ime) {
    LOGI("keyboard watch: not on this Android");
    g_vm->DetachCurrentThread();
    return nullptr;
  }
  jint ime_type = env->CallStaticIntMethod(type, ime);
  LOGI("keyboard watch running");

  bool seen = false;
  for (;;) {
    usleep(200000);
    if (env->PushLocalFrame(8) != 0) {
      env->ExceptionClear();
      continue;
    }
    bool open = env->CallStaticBooleanMethod(g_sdlactivity_cls, shown);
    if (env->ExceptionCheck()) {
      env->ExceptionClear();
      open = false;
    }
    if (!open) {
      seen = false;
    } else {
      jobject activity_now = env->GetStaticObjectField(g_sdlactivity_cls, g_singleton_fid);
      jobject win = activity_now ? env->CallObjectMethod(activity_now, get_window) : nullptr;
      jobject decor = win ? env->CallObjectMethod(win, get_decor) : nullptr;
      jobject now = decor ? env->CallObjectMethod(decor, get_insets) : nullptr;
      if (now != nullptr && !env->ExceptionCheck()) {
        bool up = env->CallBooleanMethod(now, is_visible, ime_type);
        if (env->ExceptionCheck()) {
          env->ExceptionClear();
        } else if (up) {
          seen = true;
        } else if (seen) {
          seen = false;
          env->CallStaticVoidMethod(g_sdlactivity_cls, lost);
        }
      }
      if (env->ExceptionCheck()) env->ExceptionClear();
    }
    env->PopLocalFrame(nullptr);
  }
}

static void start_keyboard_watch() {
  static bool started = false;
  if (started) return;
  started = true;
  pthread_t thread;
  if (pthread_create(&thread, nullptr, keyboard_watch, nullptr) == 0) pthread_detach(thread);
}

static void force_portrait_jni() {
  if (!g_vm) return;
  JNIEnv *env = nullptr;
  if (g_vm->GetEnv((void **)&env, JNI_VERSION_1_6) != JNI_OK || env == nullptr) return;

  if (g_sdlactivity_cls == nullptr) {
    jclass cls = env->FindClass("org/libsdl/app/SDLActivity");
    if (cls == nullptr) { if (env->ExceptionCheck()) env->ExceptionClear(); return; }
    g_sdlactivity_cls = (jclass)env->NewGlobalRef(cls);
    g_singleton_fid = env->GetStaticFieldID(cls, "mSingleton", "Lorg/libsdl/app/SDLActivity;");
    jclass actcls = env->FindClass("android/app/Activity");
    g_setreqorient_mid = env->GetMethodID(actcls, "setRequestedOrientation", "(I)V");
    env->DeleteLocalRef(actcls);
    env->DeleteLocalRef(cls);
    if (env->ExceptionCheck()) env->ExceptionClear();
    if (g_singleton_fid == nullptr || g_setreqorient_mid == nullptr) return;
    LOGI("cached SDLActivity refs");
  }

  jobject singleton = env->GetStaticObjectField(g_sdlactivity_cls, g_singleton_fid);
  if (singleton != nullptr) {
    env->CallVoidMethod(singleton, g_setreqorient_mid, 1);  // SCREEN_ORIENTATION_PORTRAIT
    if (env->ExceptionCheck()) env->ExceptionClear();
    env->DeleteLocalRef(singleton);
  }
  start_keyboard_watch();
}

static void my_setorient(int w, int h, int resizable, const char *hint) {
  (void)w;
  (void)h;
  (void)resizable;
  (void)hint;
  force_portrait_jni();
}

static void install_hooks() {
  shadowhook_init(SHADOWHOOK_MODE_UNIQUE, true);

  void *s1 = shadowhook_hook_sym_name("liblove.so", "luaL_loadbuffer",
                                      (void *)my_loadbuffer, (void **)&orig_loadbuffer);
  LOGI("hook luaL_loadbuffer stub=%p errno=%d", s1, shadowhook_get_errno());

  // Mods reach the loader through this one too (Lua's load, Steamodded's own files).
  void *s3 = shadowhook_hook_sym_name("liblove.so", "luaL_loadbufferx",
                                      (void *)my_loadbufferx, (void **)&orig_loadbufferx);
  LOGI("hook luaL_loadbufferx stub=%p errno=%d", s3, shadowhook_get_errno());

  void *s2 = shadowhook_hook_sym_name("liblove.so", "Android_JNI_SetOrientation",
                                      (void *)my_setorient, (void **)&orig_setorient);
  LOGI("hook Android_JNI_SetOrientation stub=%p errno=%d", s2, shadowhook_get_errno());
}

class BalatroPortrait : public zygisk::ModuleBase {
public:
  void onLoad(Api *api, JNIEnv *env) override {
    api_ = api;
    env_ = env;
    env->GetJavaVM(&g_vm);
  }

  void preAppSpecialize(AppSpecializeArgs *args) override {
    is_target_ = false;
    if (args->nice_name != nullptr) {
      const char *nm = env_->GetStringUTFChars(args->nice_name, nullptr);
      if (nm != nullptr) {
        is_target_ = (strcmp(nm, TARGET_PKG) == 0);
        env_->ReleaseStringUTFChars(args->nice_name, nm);
      }
    }
    if (!is_target_) {
      // not our target: let Zygisk unload us to save memory (no hooks installed)
      api_->setOption(zygisk::Option::DLCLOSE_MODULE_LIBRARY);
      return;
    }

    if (args->app_data_dir != nullptr) {
      const char *data = env_->GetStringUTFChars(args->app_data_dir, nullptr);
      if (data != nullptr) {
        snprintf(g_app_data, sizeof g_app_data, "%s", data);
        env_->ReleaseStringUTFChars(args->app_data_dir, data);
      }
    }

    // We are in Balatro and still in the zygote context (can read /data/adb and
    // the module dir). Resolve the absolute path to libshadowhook_nothing.so and
    // install the hooks NOW, so shadowhook's linker-init memory scan can dlopen
    // nothing.so before the app sandbox / SuSFS hides the module overlay.
    int dirfd = api_->getModuleDir();
    if (dirfd >= 0) {
      char link[64];
      snprintf(link, sizeof link, "/proc/self/fd/%d", dirfd);
      char dir[400];
      ssize_t n = readlink(link, dir, sizeof dir - 1);
      if (n > 0) {
        dir[n] = '\0';
        snprintf(sh_linker_nothing_override_path, sizeof sh_linker_nothing_override_path,
                 "%s/system/lib64/libshadowhook_nothing.so", dir);
        LOGI("module dir = %s", dir);
      } else {
        LOGE("readlink module dir failed");
      }
    } else {
      LOGE("getModuleDir failed");
    }

    LOGI("installing hooks in preApp (assets=%d)", kAssetCount);
    install_hooks();
  }

  void postAppSpecialize(const AppSpecializeArgs *) override {
    if (is_target_) LOGI("postAppSpecialize done (hooks were installed in preApp)");
  }

private:
  Api *api_ = nullptr;
  JNIEnv *env_ = nullptr;
  bool is_target_ = false;
};

REGISTER_ZYGISK_MODULE(BalatroPortrait)
