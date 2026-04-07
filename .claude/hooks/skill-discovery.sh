#!/bin/bash
# Skill discovery hook — triggered on UserPromptSubmit
# Lists available skills when user mentions "skill", "help", "command", or "what can"
# Non-blocking: always exits 0

# Read user prompt from stdin
PROMPT=$(cat)

# Case-insensitive check for trigger words
if echo "$PROMPT" | grep -iqE '\b(skills?|commands?|what can|help me|available|slash)\b'; then
    echo ""
    echo "Available skills (invoke with /skill-name):"
    echo ""

    SKILLS_DIR="$(pwd)/.claude/skills"
    if [ -d "$SKILLS_DIR" ]; then
        for skill_dir in "$SKILLS_DIR"/*/; do
            if [ -f "$skill_dir/SKILL.md" ]; then
                skill_name=$(basename "$skill_dir")
                # Extract description from YAML frontmatter
                desc=$(sed -n '/^---$/,/^---$/{ /^description:/{ s/^description: *//; p; q; } }' "$skill_dir/SKILL.md")
                # Check if user-invocable
                invocable=$(sed -n '/^---$/,/^---$/{ /^user-invocable:/{ s/^user-invocable: *//; p; q; } }' "$skill_dir/SKILL.md")
                if [ "$invocable" = "true" ]; then
                    printf "  /%s — %s\n" "$skill_name" "$desc"
                else
                    printf "  %s (auto) — %s\n" "$skill_name" "$desc"
                fi
            fi
        done
    fi
    echo ""
fi

exit 0
