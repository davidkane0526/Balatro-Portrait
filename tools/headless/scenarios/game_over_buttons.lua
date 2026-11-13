-- #11: Game Over's buttons, as the box opens and after Jimbo comes in. Main Menu's
-- text was drawn larger than its button was laid out for until Jimbo came in.

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'
G.SETTINGS.portrait_layout = tonumber(os.getenv('BPM_HL_LAYOUT') or '1')
G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
wait_state('BLIND_SELECT', 30)
select_blind()
wait_state('SELECTING_HAND', 30)
wait_until(function() return #G.hand.cards > 0 and input_ready() end, 15, 'cards in hand')
G.GAME.current_round.hands_left = 1
tap_node(G.hand.cards[1])
wait(0.2)
G.FUNCS.play_cards_from_highlighted()
wait_until(function() return G.STATE == G.STATES.GAME_OVER end, 40, 'game over')

local function report(tag)
    for _, key in ipairs({'notify_then_setup_run', 'go_to_menu'}) do
        local _, nodes = find({button = key})
        for _, node in ipairs(nodes or {}) do
            local rx, ry, rw, rh = rect(node)
            local texts, text_nodes = {}, {}
            local function walk(n)
                if n.config and n.config.text then
                    text_nodes[#text_nodes + 1] = n
                    local tx, ty, tw, th = rect(n)
                    texts[#texts + 1] = string.format('"%s" x=%.0f..%.0f y=%.0f..%.0f', n.config.text, tx, tx + tw, ty, ty + th)
                end
                for _, c in pairs(n.children or {}) do walk(c) end
            end
            walk(node)
            check(#texts > 0, tag .. ' ' .. key .. ' has its text')
            for _, n in ipairs(text_nodes) do
                local tx, ty, tw, th = rect(n)
                check(tx >= rx - 1 and tx + tw <= rx + rw + 1 and ty >= ry - 1 and ty + th <= ry + rh + 1,
                    string.format('%s: "%s" sits inside its button', tag, n.config.text))
                check(math.abs((tx + tw / 2) - (rx + rw / 2)) < 3, string.format('%s: "%s" is centred', tag, n.config.text))
                -- Laid out for the size it is drawn at: the bug left the layout at
                -- the old size, centred, and drew the text larger over it.
                local f = (n.config.lang or G.LANG).font
                local drawn = f.FONT:getWidth(n.config.text) * f.squish * n.config.scale * f.FONTSCALE / G.TILESIZE
                check(math.abs(n.T.w - drawn) < 0.05, string.format('%s: "%s" is laid out at the size it is drawn (%.2f vs %.2f)', tag, n.config.text, n.T.w, drawn))
            end
            log(string.format('%s %s button x=%.0f..%.0f y=%.0f..%.0f  %s', tag, key, rx, rx + rw, ry, ry + rh, table.concat(texts, ' ')))
        end
    end
end

for i, t in ipairs({0.05, 0.3, 0.6, 1.0, 1.5, 2.5, 4.0}) do
    wait_real(i == 1 and t or (t - ({0.05, 0.3, 0.6, 1.0, 1.5, 2.5, 4.0})[i - 1]))
    report(string.format('t=%.2f', t))
    shot(string.format('game_over_%02d', i))
end
