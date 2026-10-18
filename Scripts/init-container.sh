#!/usr/bin/env bash
# 初始化 CloudKit 容器：校验并导入反馈社区所需的 schema（仅支持 Development 环境）。
#
# 用法：
#   Scripts/init-container.sh -t <TEAM_ID> -c <CONTAINER_ID> [-n] [-d]
#
# 选项：
#   -t  开发团队 ID（可用 `xcrun cktool get-teams` 查看，也可用环境变量 CK_TEAM_ID）
#   -c  容器 ID，如 iCloud.in.hocg.app.example（也可用环境变量 CK_CONTAINER_ID）
#   -n  使用 Schema-NoComments.ckdb（对应 allowComments: false）
#   -d  仅校验，不导入（dry run）
#   -h  显示帮助
#
# 前置条件：已创建 Management Token（CloudKit Console → Settings → Tokens & Keys）并保存：
#   xcrun cktool save-token --type management
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM="${CK_TEAM_ID:-}"
CONTAINER="${CK_CONTAINER_ID:-}"
SCHEMA="$ROOT/Schema.ckdb"
DRY_RUN=0
ENVIRONMENT="development"

usage() { sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while getopts "t:c:ndh" opt; do
  case "$opt" in
    t) TEAM="$OPTARG" ;;
    c) CONTAINER="$OPTARG" ;;
    n) SCHEMA="$ROOT/Schema-NoComments.ckdb" ;;
    d) DRY_RUN=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

if [[ -z "$TEAM" || -z "$CONTAINER" ]]; then
  echo "错误：必须提供团队 ID 与容器 ID。" >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$SCHEMA" ]]; then
  echo "错误：找不到 schema 文件：$SCHEMA" >&2
  exit 1
fi

# 检查 token 是否可用
if ! xcrun cktool get-teams >/dev/null 2>&1; then
  echo "错误：未找到有效的 Management Token，请先执行：" >&2
  echo "  xcrun cktool save-token --type management" >&2
  exit 1
fi

COMMON=(--team-id "$TEAM" --container-id "$CONTAINER" --environment "$ENVIRONMENT")

echo "==> 校验 schema：$(basename "$SCHEMA")"
xcrun cktool validate-schema "${COMMON[@]}" --file "$SCHEMA"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "==> 仅校验模式，已跳过导入。"
  exit 0
fi

echo "==> 导入 schema 到 $CONTAINER ($ENVIRONMENT)"
xcrun cktool import-schema "${COMMON[@]}" --file "$SCHEMA"

echo "==> 导出线上 schema 以确认"
EXPORTED="$(mktemp -t ExportedSchema).ckdb"
xcrun cktool export-schema "${COMMON[@]}" --output-file "$EXPORTED"
echo "    已导出到：$EXPORTED"

cat <<MSG

完成。后续仍需手动完成（CloudKit 不支持脚本化）：
  1. 在 App 里运行一次，让 CloudKit 为每个开发者账号创建 Users 记录；
  2. 在 CloudKit Console → Public Database → Users 中找到该记录，给 roles 添加 dev；
  3. 发布前在 CloudKit Console 将 schema 部署（Deploy）到 Production。
MSG
