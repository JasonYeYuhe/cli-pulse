# CLI Pulse Task Start Prompt

Use this as the default prompt when starting a new task with Claude, Codex, or
another AI working in the private source repo.

## Copy/Paste Prompt

```md
先不要直接改代码，先做这 4 步：

1. 先阅读项目上下文
- /Users/jason/Documents/cli pulse/AGENTS.md
- /Users/jason/Documents/cli pulse/README.md
- /Users/jason/Documents/cli pulse/REPO_VISIBILITY_STRATEGY.md
- /Users/jason/Documents/cli pulse/RELEASE_WORKFLOW.md
- /Users/jason/Documents/cli pulse/BRANCHING.md

2. 先检查当前 git 状态
请先运行并确认：
```bash
git branch --show-current
git status --short --branch
```

3. 先判断这次任务应该在哪做
按下面规则决策，不要跳过：
- 如果这是当前分支同一类工作，继续在当前分支做
- 如果这是新的功能 / 新的 bug / 新的 provider / 新的集成，先从 private main 新开一个 codex/<task-name> 分支
- 如果这是 release / version bump / packaging / notarization，使用 release 分支
- 如果这是 README / docs / privacy / terms / GitHub Pages / public release notes，只走 public distribution workflow，不要动产品源码分支

4. 先把你的分支决策告诉我，再开始干活
请先用这个格式回复：
- Current branch:
- Task classification:
- Branch decision:
- Why:

如果你判断需要新分支，就直接执行：

```bash
git checkout main
git pull origin main
git checkout -b codex/<task-name>
```

然后再开始实现。

额外规则：
- 不要默认沿用旧功能分支做不相关的新任务
- 不要把 private 源码推到 public repo
- 如果分支选择不确定，优先新开分支，不要污染旧分支
- 如果你准备从 `main` 新开分支，请先确认当前 `main` 是否已经包含这个任务所需的最近基础改动；如果没有，请先明确告诉我缺了哪些分支或提交，再决定是先合并到 `main`，还是从更合适的基线分支创建新分支
```

## Short Version

```md
先不要直接开始。先读 `AGENTS.md`、`README.md`、`REPO_VISIBILITY_STRATEGY.md`、`RELEASE_WORKFLOW.md`、`BRANCHING.md`，然后运行 `git branch --show-current` 和 `git status --short --branch`。先判断这次任务是继续当前分支，还是应该从 private `main` 新开 `codex/<task-name>`，还是属于 release / public distribution 工作。先把分支决策告诉我，再开始改代码。如果准备从 `main` 新开分支，请先确认 `main` 已经包含这次任务所需的最近基础改动；如果没有，先说明缺口，再决定基线。
```

## When To Use

- Starting a brand-new feature
- Starting a new provider integration
- Starting a bug fix unrelated to the current branch
- Handing work to another AI after context switching
- Restarting work after a long gap and you want branch discipline first

## Notes

- This prompt is for the private source repo workflow.
- It is intentionally strict about branch choice so unrelated work does not get
  mixed into old task branches.
- Public distribution work should follow `RELEASE_WORKFLOW.md`, not normal
  source feature branch flow.
