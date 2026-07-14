return {
    fps = 10,
    effects = {
        ["Sparkle"] = {
            target = "Workspace.HandoffTest.Crate.Sparkle",
            events = {
                [10] = {action = "emit", count = 15},
            },
        },
    },
}