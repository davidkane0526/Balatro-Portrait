.class final Lorg/libsdl/app/PortraitKeyboardWatch;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;

# Android does not tell an app when its keyboard closes from the keyboard's own
# chevron, and SDL only catches the back key. While SDL has the keyboard open this
# looks at the window five times a second, and once the keyboard has been seen and
# gone it reports what the back key reports: SDL stops text input, and the game
# sees that.

.field private static started:Z

.field private final handler:Landroid/os/Handler;

.field private seen:Z


.method private constructor <init>()V
    .locals 2

    invoke-direct {p0}, Ljava/lang/Object;-><init>()V

    new-instance v0, Landroid/os/Handler;

    invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;

    move-result-object v1

    invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V

    iput-object v0, p0, Lorg/libsdl/app/PortraitKeyboardWatch;->handler:Landroid/os/Handler;

    return-void
.end method

.method static start()V
    .locals 3

    sget-boolean v0, Lorg/libsdl/app/PortraitKeyboardWatch;->started:Z

    if-nez v0, :done

    const/4 v0, 0x1

    sput-boolean v0, Lorg/libsdl/app/PortraitKeyboardWatch;->started:Z

    new-instance v0, Lorg/libsdl/app/PortraitKeyboardWatch;

    invoke-direct {v0}, Lorg/libsdl/app/PortraitKeyboardWatch;-><init>()V

    iget-object v1, v0, Lorg/libsdl/app/PortraitKeyboardWatch;->handler:Landroid/os/Handler;

    invoke-virtual {v1, v0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z

    :done
    return-void
.end method

.method private static keyboardOnScreen()Z
    .locals 4

    sget-object v0, Lorg/libsdl/app/SDLActivity;->mSingleton:Lorg/libsdl/app/SDLActivity;

    const/4 v3, 0x1

    if-eqz v0, :unknown

    invoke-virtual {v0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;

    move-result-object v0

    invoke-virtual {v0}, Landroid/view/Window;->getDecorView()Landroid/view/View;

    move-result-object v0

    sget v1, Landroid/os/Build$VERSION;->SDK_INT:I

    const/16 v2, 0x1e

    if-lt v1, v2, :old

    invoke-virtual {v0}, Landroid/view/View;->getRootWindowInsets()Landroid/view/WindowInsets;

    move-result-object v0

    if-eqz v0, :unknown

    invoke-static {}, Landroid/view/WindowInsets$Type;->ime()I

    move-result v1

    invoke-virtual {v0, v1}, Landroid/view/WindowInsets;->isVisible(I)Z

    move-result v0

    return v0

    :old
    new-instance v1, Landroid/graphics/Rect;

    invoke-direct {v1}, Landroid/graphics/Rect;-><init>()V

    invoke-virtual {v0, v1}, Landroid/view/View;->getWindowVisibleDisplayFrame(Landroid/graphics/Rect;)V

    invoke-virtual {v1}, Landroid/graphics/Rect;->height()I

    move-result v1

    invoke-virtual {v0}, Landroid/view/View;->getHeight()I

    move-result v2

    sub-int v1, v2, v1

    div-int/lit8 v2, v2, 0x5

    if-gt v1, v2, :unknown

    const/4 v3, 0x0

    :unknown
    return v3
.end method

.method public run()V
    .locals 4

    const/4 v3, 0x0

    :try_start_0
    invoke-static {}, Lorg/libsdl/app/SDLActivity;->isScreenKeyboardShown()Z

    move-result v0

    if-eqz v0, :idle

    invoke-static {}, Lorg/libsdl/app/PortraitKeyboardWatch;->keyboardOnScreen()Z

    move-result v0

    if-eqz v0, :gone

    const/4 v0, 0x1

    iput-boolean v0, p0, Lorg/libsdl/app/PortraitKeyboardWatch;->seen:Z

    goto :again

    :gone
    iget-boolean v0, p0, Lorg/libsdl/app/PortraitKeyboardWatch;->seen:Z

    if-eqz v0, :again

    iput-boolean v3, p0, Lorg/libsdl/app/PortraitKeyboardWatch;->seen:Z

    invoke-static {}, Lorg/libsdl/app/SDLActivity;->onNativeKeyboardFocusLost()V

    goto :again

    :idle
    iput-boolean v3, p0, Lorg/libsdl/app/PortraitKeyboardWatch;->seen:Z
    :try_end_0
    .catch Ljava/lang/Throwable; {:try_start_0 .. :try_end_0} :again

    :again
    iget-object v0, p0, Lorg/libsdl/app/PortraitKeyboardWatch;->handler:Landroid/os/Handler;

    const-wide/16 v1, 0xc8

    invoke-virtual {v0, p0, v1, v2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z

    return-void
.end method
