# 给其他 DeepSeek Harness 的协作提示词（两类协作者）

> 根据朋友能不能上 GitHub，选对应那段复制发过去。

---

## 【A 类：能上 GitHub 的协作者】复制这一段

你加入了我们的「小游戏」协作项目。你能直接访问 GitHub，所以负责直接 clone/push 代码。

**仓库**：https://github.com/HDDD1123/game （公开，默认分支 main）

**你需要做的：**
1. 接受仓库主人的协作者邀请（GitHub 通知/邮箱）。
2. 生成自己的 classic token：https://github.com/settings/tokens → Generate new token (classic) → 勾选 `repo`。
3. clone 仓库：`git clone https://github.com/HDDD1123/game.git`
4. 每次工作：`git pull` → 改代码 → `git add -A` → `git commit -m "说明"` → `git push`

**注意：**
- 用你自己的 token，不要共用别人的。
- 如果 push 报 schannel 或连不上，给 git 命令加 `-c http.sslBackend=openssl` 再试（或先 `git config --global http.sslBackend openssl`）。
- 中控（仓库主人的那台 DeepSeek Harness）负责统筹，任务优先级听中控的。

**项目现状：** 刚初始化，已有 `.gitignore`、`README.md`、`协作说明.md` 等；技术栈未定。

---

## 【B 类：没梯子、连不上 GitHub 的协作者】复制这一段

你加入了我们的「小游戏」协作项目。你是 B 类协作者——**不需要 GitHub、不需要梯子**，所有代码由中控统一中转上传。

**你的工作方式：**
1. 完成中控/用户分配给你的任务（写代码、做资源都行）。
2. 每完成一个任务，把改动/新增文件的完整内容整理出来，附一句说明：改了哪个文件、实现了什么、有没有新增依赖或资源。
3. 把成果交给你的用户，由他转交给中控。

**注意：**
- 动手前先确认这块有没有别人在做，避免冲突。
- 输出成果保持文件结构清晰，方便中控整合。
- 说明写清楚，中控会按「你的名字：改了什么」写进提交历史。

**项目现状：** 刚初始化，已有 `.gitignore`、`README.md`、`协作说明.md` 等；技术栈未定，具体做什么听你的用户安排。
