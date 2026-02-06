--- Adept NPC dialogue tree - Multi-branch quest system
--- Quest involves crystal ball, gnomos, and multiple resolution paths
--- Includes quick paths for players who want to skip to gameplay
return {
    id = "adept_house_dialogue",
    start_node = "greeting",
    nodes = {
        -- Main hub node with conditional options
        greeting = {
            text = "...",
            options = {
                -- First meeting path
                { text = "Hello?", next = "introduction", condition = "not_met_adept" },
                -- Returning visitor paths
                { text = "I found your crystal ball.", next = "crystal_found_roof", condition = "met_adept", condition2 = "has_item_crystal_ball", condition3 = "not_has_item_adept_apology" },
                { text = "About the apology letter...", next = "apology_reminder", condition = "has_item_adept_apology", condition2 = "not_apology_delivered_to_gnomos" },
                { text = "The gnomos are dead.", next = "gnomos_defeated_check", condition = "met_adept", condition2 = "defeated_boss_gnomo_brothers", condition3 = "not_crystal_returned" },
                { text = "I delivered your apology.", next = "apology_delivered", condition = "apology_delivered_to_gnomos", condition2 = "not_received_orb" },
                { text = "What can you tell me about myself?", next = "memory_loss", condition = "met_adept" },
                { text = "About that chest...", next = "about_chest", condition = "met_adept", condition2 = "not_asked_about_chest" },
                { text = "Any luck finding the crystal ball?", next = "crystal_reminder", condition = "asked_about_chest", condition2 = "not_crystal_returned" },
                { text = "Tell me about the orb.", next = "orb_info", condition = "received_orb" },
                { text = "Leave", next = nil, condition = "met_adept" },
            },
        },

        -- First meeting introduction - immediately explains finding player
        introduction = {
            text = "Ah, you're awake! I found you collapsed near the cliffside. Brought you inside to rest.",
            actions = { "set_flag_met_adept" },
            options = {
                { text = "What's in that chest?", next = "about_chest" },
                { text = "I don't remember anything.", next = "dont_remember" },
                { text = "Where am I?", next = "where_am_i" },
                { text = "Thank you for saving me.", next = "thanks_for_saving" },
                { text = "Leave", next = nil },
            },
        },

        where_am_i = {
            text = "This is my cottage, at the edge of the old woods. I've lived here for many years now, studying what remains of the ancient texts.",
            options = {
                { text = "What's in that chest?", next = "about_chest", condition = "not_asked_about_chest" },
                { text = "Who are you?", next = "who_are_you" },
                { text = "I don't remember how I got here.", next = "dont_remember" },
                { text = "Leave", next = nil },
            },
        },

        who_are_you = {
            text = "I am... well, they call me the Adept now. I was a warrior once, long ago. These days I prefer the company of books to swords.",
            options = {
                { text = "What's in that chest?", next = "about_chest", condition = "not_asked_about_chest" },
                { text = "I don't remember anything about myself.", next = "dont_remember" },
                { text = "What do you study?", next = "what_study" },
                { text = "Leave", next = nil },
            },
        },

        what_study = {
            text = "The nature of this realm. Its history. Its... peculiarities. There is much that is forgotten, much that perhaps should stay forgotten.",
            options = {
                { text = "What's in that chest?", next = "about_chest", condition = "not_asked_about_chest" },
                { text = "I don't remember anything.", next = "dont_remember" },
                { text = "Leave", next = nil },
            },
        },

        thanks_for_saving = {
            text = "Think nothing of it. We must help each other in these troubled times.",
            options = {
                { text = "What's in that chest?", next = "about_chest", condition = "not_asked_about_chest" },
                { text = "I don't remember anything.", next = "dont_remember" },
                { text = "Leave", next = nil },
            },
        },

        dont_remember = {
            text = "Memory loss? That must be frightening. Perhaps your memories will return in time. For now, focus on the present.",
            options = {
                { text = "What's in that chest?", next = "about_chest", condition = "not_asked_about_chest" },
                { text = "Is there anything you can tell me?", next = "tell_me_more" },
                { text = "Leave", next = nil },
            },
        },

        tell_me_more = {
            text = "I wish I could help more. When I found you, you carried no belongings, no identification. Only... a strange energy about you.",
            options = {
                { text = "What's in that chest?", next = "about_chest", condition = "not_asked_about_chest" },
                { text = "Strange energy?", next = "strange_energy" },
                { text = "Leave", next = nil },
            },
        },

        strange_energy = {
            text = "It's faded now. Perhaps I imagined it. Old men see many things that aren't there. Pay it no mind.",
            options = {
                { text = "What's in that chest?", next = "about_chest", condition = "not_asked_about_chest" },
                { text = "Leave", next = nil },
            },
        },

        -- Memory/lore branch (returning visitors)
        memory_loss = {
            text = "Ah, still nothing? I'm sorry. Memory is a fragile thing. Sometimes trauma buries it deep. Sometimes... it was never there to begin with.",
            options = {
                { text = "What do you mean 'never there'?", next = "never_there" },
                { text = "What happened to me?", next = "what_happened" },
                { text = "Leave", next = nil },
            },
        },

        never_there = {
            text = "Just the ramblings of an old scholar. Don't mind me. Focus on moving forward - that's what matters.",
            options = {
                { text = "You're hiding something.", next = "hiding_something" },
                { text = "Leave", next = nil },
            },
        },

        hiding_something = {
            text = "We all hide things, friend. Some truths are too heavy to carry. When you're ready to bear the weight... perhaps then we'll talk more.",
            options = {
                { text = "I'm ready now.", next = "not_ready" },
                { text = "Leave", next = nil },
            },
        },

        not_ready = {
            text = "No. You're not. Trust me on this. Go, explore this world. Learn its ways. Then come back, and we shall see.",
            options = {
                { text = "Leave", next = nil },
            },
        },

        what_happened = {
            text = "I found you near the cliffs, barely alive. No wounds I could see, yet you wouldn't wake for three days. It was as if your spirit was... elsewhere.",
            options = {
                { text = "Elsewhere?", next = "spirit_elsewhere" },
                { text = "Three days?", next = "three_days" },
                { text = "Leave", next = nil },
            },
        },

        spirit_elsewhere = {
            text = "A figure of speech. Nothing more. You're here now, that's what matters. The past is gone; only the path forward remains.",
            options = {
                { text = "You speak strangely.", next = "hiding_something" },
                { text = "Leave", next = nil },
            },
        },

        three_days = {
            text = "Indeed. I wasn't sure you'd wake at all. But here you are, hale and whole. A small miracle, perhaps.",
            options = {
                { text = "Thank you for watching over me.", next = "watching_over" },
                { text = "Leave", next = nil },
            },
        },

        watching_over = {
            text = "It's the least I could do. We get few visitors here. It was... nice to have company, even if you weren't much for conversation.",
            options = {
                { text = "Leave", next = nil },
            },
        },

        -- Chest/Quest branch - simplified, no mention of contents
        about_chest = {
            text = "I can't remember what's inside, but it's yours if you can get my crystal ball back from the gnomos.",
            actions = { "set_flag_asked_about_chest" },
            options = {
                { text = "I'll find it!", next = "accept_quest" },
                { text = "Crystal ball?", next = "crystal_ball_info" },
                { text = "Tell me about the gnomos.", next = "gnomos_info" },
                { text = "Leave", next = nil },
            },
        },

        crystal_ball_info = {
            text = "A family heirloom imbued with ancient magic. Allows one to travel great distances in the blink of an eye. I used it rarely, but its loss pains me greatly.",
            options = {
                { text = "I'll find it!", next = "accept_quest" },
                { text = "The gnomos took it?", next = "gnomos_took_it" },
                { text = "Leave", next = nil },
            },
        },

        gnomos_info = {
            text = "Nasty little creatures. They've infested the caves below the valley. They steal anything shiny - coins, jewelry, magical artifacts.",
            options = {
                { text = "I'll find it!", next = "accept_quest" },
                { text = "How do you know they took it?", next = "how_know_gnomos" },
                { text = "Leave", next = nil },
            },
        },

        gnomos_took_it = {
            text = "Who else? They raid my garden, steal my belongings. I saw them skulking about the night it vanished. It must have been them.",
            options = {
                { text = "I'll find it!", next = "accept_quest" },
                { text = "Are you certain?", next = "how_know_gnomos" },
                { text = "Leave", next = nil },
            },
        },

        how_know_gnomos = {
            text = "I... well, I assumed. They're always stealing things. Who else would take it? It was on my reading table one night, gone the next morning. It must have been those gnomos.",
            options = {
                { text = "I'll find it!", next = "accept_quest" },
                { text = "Leave", next = nil },
            },
        },

        accept_quest = {
            text = "Thank you! Be careful in those caves.",
            options = {
                { text = "Leave", next = nil },
            },
        },

        crystal_reminder = {
            text = "Still no sign of my crystal ball? Those gnomos must be hoarding it deep in their caves.",
            options = {
                { text = "I'll keep looking.", next = nil },
                { text = "Tell me about the gnomos again.", next = "gnomos_info" },
                { text = "Leave", next = nil },
            },
        },

        -- Crystal ball found on roof - branching based on gnomo status
        crystal_found_roof = {
            text = "You found it! Where was it?",
            options = {
                { text = "On your roof.", next = "roof_revelation" },
                { text = "Leave", next = nil },
            },
        },

        roof_revelation = {
            text = "The roof? But... but I was so certain... Oh no. Oh dear. The gnomos... I accused them wrongfully. I've been saying terrible things about them to everyone who passes through.",
            options = {
                { text = "They're still alive. You could apologize.", next = "gnomos_alive_path", condition = "not_defeated_boss_gnomo_brothers" },
                { text = "About the gnomos...", next = "gnomos_dead_revelation", condition = "defeated_boss_gnomo_brothers" },
                { text = "Leave", next = nil },
            },
        },

        -- Path A: Gnomos alive, can deliver apology
        gnomos_alive_path = {
            text = "You're right. I should make amends. Here, take this letter. It contains my sincerest apology. If you could deliver it to them... and please, give them back the crystal ball as a peace offering.",
            actions = { "give_item_adept_apology", "set_flag_crystal_returned" },
            options = {
                { text = "I'll deliver it.", next = "deliver_apology_accept" },
                { text = "You want me to give them the crystal ball?", next = "give_ball_explanation" },
                { text = "Leave", next = nil },
            },
        },

        give_ball_explanation = {
            text = "I've done them a great wrong. The crystal ball is precious, but my conscience is worth more. Besides, perhaps they'll return it one day, once trust is rebuilt.",
            options = {
                { text = "I'll deliver it.", next = "deliver_apology_accept" },
                { text = "Are you sure?", next = "sure_about_ball" },
                { text = "Leave", next = nil },
            },
        },

        sure_about_ball = {
            text = "I am. Material things come and go. Guilt lingers forever. Please, take the apology to them. Return here after, and I'll give you the key and what reward I can.",
            options = {
                { text = "I'll do it.", next = "deliver_apology_accept" },
                { text = "Leave", next = nil },
            },
        },

        deliver_apology_accept = {
            text = "Thank you. The gnomo brothers dwell in the caves below the valley. They're hostile, but perhaps if you approach peacefully with the letter... be careful.",
            options = {
                { text = "Leave", next = nil },
            },
        },

        -- Reminder for players who have the apology but haven't delivered it
        apology_reminder = {
            text = "You still have my letter? Please, take it to the gnomo brothers in the caves below the valley. I need to make amends for my false accusations.",
            options = {
                { text = "I'll deliver it.", next = nil },
                { text = "Where are the gnomos again?", next = "apology_directions" },
                { text = "Leave", next = nil },
            },
        },

        apology_directions = {
            text = "The caves below the valley. They're hostile creatures, but perhaps if you approach peacefully with my letter, they'll hear you out. Please be careful.",
            options = {
                { text = "Leave", next = nil },
            },
        },

        -- Path B: Defeated gnomos before finding ball
        gnomos_defeated_check = {
            text = "Dead? You killed them? But... the crystal ball. Did they have it?",
            options = {
                { text = "No. I didn't find it on them.", next = "gnomos_defeated_no_ball", condition = "not_has_item_crystal_ball" },
                { text = "Actually, I found it elsewhere.", next = "crystal_found_roof", condition = "has_item_crystal_ball" },
                { text = "Leave", next = nil },
            },
        },

        gnomos_defeated_no_ball = {
            text = "They... they didn't have it? Then where... Oh gods. What have I done? I sent you after innocent creatures. Their blood is on my hands.",
            actions = { "set_flag_gnomos_wrongly_killed" },
            options = {
                { text = "You couldn't have known.", next = "guilt_response" },
                { text = "Where else could the ball be?", next = "guilt_where_else" },
                { text = "Leave", next = nil },
            },
        },

        guilt_response = {
            text = "I should have looked harder. I was so quick to blame them... Here. Take the key. It's the least I can do. But I fear no reward can ease my conscience now.",
            actions = { "give_item_adept_key" },
            options = {
                { text = "I'll keep looking for the crystal ball.", next = "keep_looking" },
                { text = "Try not to blame yourself too much.", next = "self_blame" },
                { text = "Leave", next = nil },
            },
        },

        guilt_where_else = {
            text = "I don't know... It must be around here somewhere. Could you look? If you find it, then I truly am a fool and a murderer.",
            options = {
                { text = "I'll look around.", next = nil },
                { text = "Leave", next = nil },
            },
        },

        keep_looking = {
            text = "Please do. And if you find it... bring it back. Not for me, but... I need to know the truth. Even if it damns me.",
            options = {
                { text = "Leave", next = nil },
            },
        },

        self_blame = {
            text = "How can I not? I called them thieves. Monsters. And they were innocent all along. Go. Take the key. I need to be alone with my shame.",
            options = {
                { text = "Leave", next = nil },
            },
        },

        -- Path C: Gnomos dead, found ball after
        gnomos_dead_revelation = {
            text = "No... please don't tell me...",
            options = {
                { text = "I killed them. Before I found the ball.", next = "gnomos_dead_guilt" },
                { text = "Leave", next = nil },
            },
        },

        gnomos_dead_guilt = {
            text = "Then I have sent you to murder innocents. The crystal ball was on my own roof while I condemned them as thieves. I am no better than the monsters I warned you about.",
            actions = { "set_flag_gnomos_wrongly_killed", "set_flag_crystal_returned", "take_item_crystal_ball" },
            options = {
                { text = "You made a mistake. We all do.", next = "mistake_comfort" },
                { text = "What's done is done.", next = "done_is_done" },
                { text = "Leave", next = nil },
            },
        },

        mistake_comfort = {
            text = "A mistake that cost lives. Here, take the key. And the crystal ball... keep it. I cannot bear to look at it. Perhaps you can imbue it with better memories than mine.",
            actions = { "give_item_adept_key" },
            options = {
                { text = "I could use its power to help others.", next = "imbue_crystal" },
                { text = "Are you sure you want me to have it?", next = "sure_keep_ball" },
                { text = "Leave", next = nil },
            },
        },

        done_is_done = {
            text = "Cold comfort, but true. Take the key. And the crystal ball - I cannot keep it. Every time I look at it, I'll see their faces.",
            actions = { "give_item_adept_key" },
            options = {
                { text = "The ball could still do good.", next = "imbue_crystal" },
                { text = "I'll take it.", next = "receive_orb" },
                { text = "Leave", next = nil },
            },
        },

        sure_keep_ball = {
            text = "I am. Perhaps in your hands it can be a tool for good, rather than a reminder of my failure. Let me prepare it for you.",
            options = {
                { text = "Thank you.", next = "imbue_crystal" },
                { text = "Leave", next = nil },
            },
        },

        -- Apology delivered (set by gnomo dialogue)
        apology_delivered = {
            text = "You delivered my letter? And they... accepted it? Truly?",
            options = {
                { text = "They did. They forgave you.", next = "forgiveness_relief" },
                { text = "It wasn't easy, but yes.", next = "forgiveness_relief" },
                { text = "Leave", next = nil },
            },
        },

        forgiveness_relief = {
            text = "I don't deserve their forgiveness, but I'm grateful for it. You've done a good thing today. Here - the key, as promised. And the crystal ball... I want you to have it.",
            actions = { "give_item_adept_key", "take_item_adept_apology", "take_item_crystal_ball" },
            options = {
                { text = "Thank you.", next = "imbue_crystal" },
                { text = "You're giving me the crystal ball?", next = "giving_ball_reason" },
                { text = "Leave", next = nil },
            },
        },

        giving_ball_reason = {
            text = "You've earned it. You could have simply killed them and taken what you wanted. Instead, you chose the harder path. The path of peace. That deserves reward.",
            options = {
                { text = "I'll use it wisely.", next = "imbue_crystal" },
                { text = "Leave", next = nil },
            },
        },

        -- Imbue crystal ball -> Orb of Teleportation
        imbue_crystal = {
            text = "Before I give it to you, let me attune it to your spirit. This way, only you can use its power. Hold still... there. It is done.",
            options = {
                { text = "What can it do?", next = "orb_abilities" },
                { text = "Thank you.", next = "receive_orb" },
                { text = "Leave", next = nil },
            },
        },

        orb_abilities = {
            text = "With this Orb of Teleportation, you can travel instantly to any location you have visited. Simply focus on the place in your mind, and the orb will take you there.",
            options = {
                { text = "That's incredible.", next = "receive_orb" },
                { text = "Leave", next = nil },
            },
        },

        receive_orb = {
            text = "Use it well. And... thank you. For everything.",
            actions = { "give_item_orb_of_teleportation", "set_flag_received_orb" },
            options = {
                { text = "Farewell, Adept.", next = nil },
            },
        },

        -- Post-quest dialogue
        orb_info = {
            text = "The Orb of Teleportation will serve you well in your journeys. Focus on a place you've been, and it will take you there. Be careful where you use it - some places don't take kindly to sudden arrivals.",
            options = {
                { text = "Leave", next = nil },
            },
        },
    },
}
