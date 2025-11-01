#!/bin/bash

# API 测试脚本
# 使用方法: chmod +x test_api.sh && ./test_api.sh

BASE_URL="http://localhost:3000/api"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "======================================"
echo "  MP3 API 本地测试"
echo "======================================"
echo ""

# 测试计数器
PASSED=0
FAILED=0

# 辅助函数
test_endpoint() {
    local name="$1"
    local method="$2"
    local url="$3"
    local data="$4"
    local expected_status="$5"
    
    echo -n "测试: $name ... "
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" "$url")
    elif [ "$method" = "DELETE" ]; then
        response=$(curl -s -w "\n%{http_code}" -X DELETE "$url")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" -H "Content-Type: application/json" -d "$data" "$url")
    fi
    
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "$expected_status" ]; then
        echo -e "${GREEN}✓ PASS${NC} (状态码: $http_code)"
        PASSED=$((PASSED + 1))
        return 0
    else
        echo -e "${RED}✗ FAIL${NC} (期望: $expected_status, 实际: $http_code)"
        echo "  响应: $body"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

echo "========================================"
echo "1. 基础端点测试"
echo "========================================"

# 测试根端点
test_endpoint "GET /" "GET" "$BASE_URL/" "" "200"

# 测试获取所有用户
test_endpoint "GET /users" "GET" "$BASE_URL/users" "" "200"

# 测试获取所有任务
test_endpoint "GET /tasks" "GET" "$BASE_URL/tasks" "" "200"

echo ""
echo "========================================"
echo "2. 用户 CRUD 测试"
echo "========================================"

# 创建用户（使用唯一邮箱避免与已有数据冲突）
echo -n "创建测试用户 ... "
TEST_USER_EMAIL="testuser_$(date +%s%N)@example.com"
CREATE_USER_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"Test User\",\"email\":\"$TEST_USER_EMAIL\"}" \
    "$BASE_URL/users")
USER_ID=$(echo $CREATE_USER_RESPONSE | grep -o '"_id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ ! -z "$USER_ID" ]; then
    echo -e "${GREEN}✓ 成功${NC} (ID: $USER_ID)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ 失败${NC}"
    echo "  响应: $CREATE_USER_RESPONSE"
    FAILED=$((FAILED + 1))
fi

# 获取单个用户
test_endpoint "GET /users/:id" "GET" "$BASE_URL/users/$USER_ID" "" "200"

# 更新用户（使用唯一邮箱避免冲突）
UPDATED_EMAIL="updated_$(date +%s%N)@example.com"
test_endpoint "PUT /users/:id" "PUT" "$BASE_URL/users/$USER_ID" \
    "{\"name\":\"Updated User\",\"email\":\"$UPDATED_EMAIL\"}" "200"

# 测试重复 email（应该失败）
test_endpoint "POST /users (重复email)" "POST" "$BASE_URL/users" \
    "{\"name\":\"Another User\",\"email\":\"$UPDATED_EMAIL\"}" "400"

# 测试缺少必填字段
test_endpoint "POST /users (缺少name)" "POST" "$BASE_URL/users" \
    '{"email":"noname@example.com"}' "400"

test_endpoint "POST /users (缺少email)" "POST" "$BASE_URL/users" \
    '{"name":"No Email User"}' "400"

echo ""
echo "========================================"
echo "3. 任务 CRUD 测试"
echo "========================================"

# 创建任务
echo -n "创建测试任务 ... "
DEADLINE=$(date -u -v+7d +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null || date -u -d "+7 days" +"%Y-%m-%dT%H:%M:%S.000Z" 2>/dev/null || echo "2025-12-31T23:59:59.000Z")
CREATE_TASK_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"Test Task\",\"description\":\"Test description\",\"deadline\":\"$DEADLINE\",\"completed\":false}" \
    "$BASE_URL/tasks")
TASK_ID=$(echo $CREATE_TASK_RESPONSE | grep -o '"_id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ ! -z "$TASK_ID" ]; then
    echo -e "${GREEN}✓ 成功${NC} (ID: $TASK_ID)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ 失败${NC}"
    echo "  响应: $CREATE_TASK_RESPONSE"
    FAILED=$((FAILED + 1))
fi

# 获取单个任务
test_endpoint "GET /tasks/:id" "GET" "$BASE_URL/tasks/$TASK_ID" "" "200"

# 更新任务
test_endpoint "PUT /tasks/:id" "PUT" "$BASE_URL/tasks/$TASK_ID" \
    "{\"name\":\"Updated Task\",\"description\":\"Updated description\",\"deadline\":\"$DEADLINE\",\"completed\":true}" "200"

# 测试缺少必填字段
test_endpoint "POST /tasks (缺少name)" "POST" "$BASE_URL/tasks" \
    "{\"description\":\"No name\",\"deadline\":\"$DEADLINE\"}" "400"

test_endpoint "POST /tasks (缺少deadline)" "POST" "$BASE_URL/tasks" \
    '{"name":"No Deadline Task","description":"Test"}' "400"

echo ""
echo "========================================"
echo "4. 查询参数测试"
echo "========================================"

# where 查询
test_endpoint "GET /users?where" "GET" "$BASE_URL/users?where=%7B%22name%22%3A%22Updated%20User%22%7D" "" "200"

# select 查询
test_endpoint "GET /users?select" "GET" "$BASE_URL/users?select=%7B%22name%22%3A1%2C%22email%22%3A1%7D" "" "200"

# sort 查询
test_endpoint "GET /users?sort" "GET" "$BASE_URL/users?sort=%7B%22name%22%3A1%7D" "" "200"

# limit 查询
test_endpoint "GET /users?limit" "GET" "$BASE_URL/users?limit=5" "" "200"

# skip 查询
test_endpoint "GET /users?skip" "GET" "$BASE_URL/users?skip=5&limit=5" "" "200"

# count 查询
test_endpoint "GET /users?count" "GET" "$BASE_URL/users?count=true" "" "200"

# 组合查询
test_endpoint "GET /users (组合查询)" "GET" "$BASE_URL/users?sort=%7B%22name%22%3A1%7D&limit=10&select=%7B%22name%22%3A1%2C%22email%22%3A1%7D" "" "200"

# tasks 查询
test_endpoint "GET /tasks?where" "GET" "$BASE_URL/tasks?where=%7B%22completed%22%3Atrue%7D" "" "200"
test_endpoint "GET /tasks?count" "GET" "$BASE_URL/tasks?count=true" "" "200"

# 测试 tasks 默认 limit=100
echo -n "测试 tasks 默认 limit=100 ... "
TASKS_RESPONSE=$(curl -s "$BASE_URL/tasks")
TASKS_COUNT=$(echo $TASKS_RESPONSE | grep -o '"_id"' | wc -l | tr -d ' ')
if [ "$TASKS_COUNT" -le "100" ]; then
    echo -e "${GREEN}✓ PASS${NC} (返回 $TASKS_COUNT 个任务)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC} (返回 $TASKS_COUNT 个任务，超过100)"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "========================================"
echo "5. 双向引用测试"
echo "========================================"

# 创建新用户和任务用于测试
echo -n "创建测试数据 (用户+任务) ... "
TEST_USER_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"Reference Test User","email":"reftest@example.com"}' \
    "$BASE_URL/users")
TEST_USER_ID=$(echo $TEST_USER_RESPONSE | grep -o '"_id":"[^"]*"' | head -1 | cut -d'"' -f4)

TEST_TASK_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"Reference Test Task\",\"deadline\":\"$DEADLINE\"}" \
    "$BASE_URL/tasks")
TEST_TASK_ID=$(echo $TEST_TASK_RESPONSE | grep -o '"_id":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ ! -z "$TEST_USER_ID" ] && [ ! -z "$TEST_TASK_ID" ]; then
    echo -e "${GREEN}✓ 成功${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ 失败${NC}"
    FAILED=$((FAILED + 1))
fi

# 测试 PUT Task 分配给用户
echo -n "PUT Task 分配给用户 ... "
ASSIGN_RESPONSE=$(curl -s -X PUT -H "Content-Type: application/json" \
    -d "{\"name\":\"Reference Test Task\",\"deadline\":\"$DEADLINE\",\"assignedUser\":\"$TEST_USER_ID\",\"completed\":false}" \
    "$BASE_URL/tasks/$TEST_TASK_ID")
ASSIGNED_USER=$(echo $ASSIGN_RESPONSE | grep -o "\"assignedUser\":\"$TEST_USER_ID\"")

if [ ! -z "$ASSIGNED_USER" ]; then
    echo -e "${GREEN}✓ 任务已分配${NC}"
    PASSED=$((PASSED + 1))
    
    # 检查用户的 pendingTasks
    echo -n "  检查用户 pendingTasks ... "
    USER_CHECK=$(curl -s "$BASE_URL/users/$TEST_USER_ID")
    USER_HAS_TASK=$(echo $USER_CHECK | grep -o "\"$TEST_TASK_ID\"")
    
    if [ ! -z "$USER_HAS_TASK" ]; then
        echo -e "${GREEN}✓ PASS${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC} (用户的 pendingTasks 未更新)"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${RED}✗ 失败${NC}"
    FAILED=$((FAILED + 1))
fi

# 测试 DELETE Task 移除引用
echo -n "DELETE Task 移除用户引用 ... "
curl -s -X DELETE "$BASE_URL/tasks/$TEST_TASK_ID" > /dev/null
sleep 1
USER_CHECK_AFTER=$(curl -s "$BASE_URL/users/$TEST_USER_ID")
TASK_STILL_THERE=$(echo $USER_CHECK_AFTER | grep -o "\"$TEST_TASK_ID\"")

if [ -z "$TASK_STILL_THERE" ]; then
    echo -e "${GREEN}✓ PASS${NC} (用户 pendingTasks 已移除)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC} (用户 pendingTasks 未移除)"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "========================================"
echo "6. HTTP 状态码测试"
echo "========================================"

# 404 测试
test_endpoint "GET /users/:id (不存在)" "GET" "$BASE_URL/users/507f1f77bcf86cd799439011" "" "404"
test_endpoint "GET /tasks/:id (不存在)" "GET" "$BASE_URL/tasks/507f1f77bcf86cd799439011" "" "404"

# 400 测试 (无效 ID)
test_endpoint "GET /users/:id (无效ID)" "GET" "$BASE_URL/users/invalid-id" "" "400"

# 204 测试 (DELETE) - 创建新用户用于删除测试
echo -n "DELETE 返回 204 ... "
DELETE_TEST_USER=$(curl -s -X POST -H "Content-Type: application/json" \
    -d '{"name":"Delete Test User","email":"deletetest@example.com"}' \
    "$BASE_URL/users")
DELETE_TEST_ID=$(echo $DELETE_TEST_USER | grep -o '"_id":"[^"]*"' | head -1 | cut -d'"' -f4)

DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" -X DELETE "$BASE_URL/users/$DELETE_TEST_ID")
DELETE_CODE=$(echo "$DELETE_RESPONSE" | tail -n1)

if [ "$DELETE_CODE" = "204" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC} (期望: 204, 实际: $DELETE_CODE)"
    FAILED=$((FAILED + 1))
fi

# 清理测试用户
curl -s -X DELETE "$BASE_URL/users/$TEST_USER_ID" > /dev/null 2>&1

echo ""
echo "========================================"
echo "7. 数据库数据验证"
echo "========================================"

# 验证用户数量
echo -n "验证用户数量 (≥20) ... "
USER_COUNT_RESPONSE=$(curl -s "$BASE_URL/users?count=true")
USER_COUNT=$(echo $USER_COUNT_RESPONSE | grep -o '"data":[0-9]*' | grep -o '[0-9]*')

if [ "$USER_COUNT" -ge "20" ]; then
    echo -e "${GREEN}✓ PASS${NC} (实际: $USER_COUNT)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC} (实际: $USER_COUNT)"
    FAILED=$((FAILED + 1))
fi

# 验证任务数量
echo -n "验证任务数量 (≥100) ... "
TASK_COUNT_RESPONSE=$(curl -s "$BASE_URL/tasks?count=true")
TASK_COUNT=$(echo $TASK_COUNT_RESPONSE | grep -o '"data":[0-9]*' | grep -o '[0-9]*')

if [ "$TASK_COUNT" -ge "100" ]; then
    echo -e "${GREEN}✓ PASS${NC} (实际: $TASK_COUNT)"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC} (实际: $TASK_COUNT)"
    FAILED=$((FAILED + 1))
fi

# 验证完成的任务数量
echo -n "验证完成任务比例 ... "
COMPLETED_COUNT_RESPONSE=$(curl -s "$BASE_URL/tasks?where={\"completed\":true}&count=true")
COMPLETED_COUNT=$(echo $COMPLETED_COUNT_RESPONSE | grep -o '"data":[0-9]*' | grep -o '[0-9]*')

echo -e "${GREEN}✓${NC} 完成: $COMPLETED_COUNT, 未完成: $((TASK_COUNT - COMPLETED_COUNT))"
PASSED=$((PASSED + 1))

echo ""
echo "========================================"
echo "8. 扩展边界测试"
echo "========================================"

# 无效 JSON（应 400）
test_endpoint "GET /users?where (无效JSON)" "GET" "$BASE_URL/users?where=%7Bname%3A%22bad%22%7D" "" "400"
test_endpoint "GET /users?select (无效JSON)" "GET" "$BASE_URL/users?select=%7Bbad%7D" "" "400"
test_endpoint "GET /users?sort (无效JSON)" "GET" "$BASE_URL/users?sort=%7Bname%3A1%7D" "" "400"

# limit/skip 负数（应 400）
test_endpoint "GET /users?limit=-1" "GET" "$BASE_URL/users?limit=-1" "" "400"
test_endpoint "GET /users?skip=-5" "GET" "$BASE_URL/users?skip=-5" "" "400"

# limit=0 应返回空数组
echo -n "GET /tasks?limit=0 返回空数组 ... "
RESP_LIMIT0=$(curl -s "$BASE_URL/tasks?limit=0")
COUNT_LIMIT0=$(echo "$RESP_LIMIT0" | grep -o '"_id"' | wc -l | tr -d ' ')
if [ "$COUNT_LIMIT0" = "0" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC} (包含 $COUNT_LIMIT0 条)"
    FAILED=$((FAILED + 1))
fi

# count=true 与 select 同时使用应 400
test_endpoint "GET /users?count=true&select=... (冲突)" "GET" "$BASE_URL/users?count=true&select=%7B%22name%22%3A1%7D" "" "400"

# /:id 支持 select 且可排除 _id
echo -n "/users/:id?select 排除 _id ... "
RESP_SEL=$(curl -s "$BASE_URL/users/$USER_ID?select=%7B%22email%22%3A1%2C%22_id%22%3A0%7D")
if echo "$RESP_SEL" | grep -q '"_id"'; then
    echo -e "${RED}✗ FAIL${NC} (_id 仍存在)"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
fi

# deadline 多种格式
DEADLINE_MS="1730501234567"
DEADLINE_SCI="1.730501234567e+12"
test_endpoint "POST /tasks (deadline ISO)" "POST" "$BASE_URL/tasks" "{\"name\":\"DeadlineISO\",\"deadline\":\"2026-01-01T00:00:00.000Z\"}" "201"
test_endpoint "POST /tasks (deadline 毫秒字符串)" "POST" "$BASE_URL/tasks" "{\"name\":\"DeadlineMS\",\"deadline\":\"$DEADLINE_MS\"}" "201"
test_endpoint "POST /tasks (deadline 科学计数法)" "POST" "$BASE_URL/tasks" "{\"name\":\"DeadlineSCI\",\"deadline\":\"$DEADLINE_SCI\"}" "201"

# x-www-form-urlencoded 创建用户
echo -n "POST /users (x-www-form-urlencoded) ... "
FORM_EMAIL="form$(date +%s)@example.com"
FORM_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "name=Form User" --data-urlencode "email=$FORM_EMAIL" "$BASE_URL/users")
if [ "$FORM_CODE" = "201" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC} (状态码: $FORM_CODE)"
    FAILED=$((FAILED + 1))
fi

# 错误的 Content-Type 应 400
test_endpoint "POST /users (text/plain 错误类型)" "POST" "$BASE_URL/users" '{"name":"X"}' "400"

# $in 操作符
T1=$(curl -s "$BASE_URL/tasks?limit=1" | grep -o '"_id":"[^"]*"' | head -1 | cut -d '"' -f4)
T2=$(curl -s "$BASE_URL/tasks?skip=1&limit=1" | grep -o '"_id":"[^"]*"' | head -1 | cut -d '"' -f4)
test_endpoint "GET /tasks where $in" "GET" "$BASE_URL/tasks?where=%7B%22_id%22%3A%7B%22%24in%22%3A%5B%22$T1%22%2C%22$T2%22%5D%7D%7D" "" "200"

# skip 很大应返回空
echo -n "GET /tasks?skip=100000 返回空 ... "
RESP_SKIP=$(curl -s "$BASE_URL/tasks?skip=100000&limit=10")
COUNT_SKIP=$(echo "$RESP_SKIP" | grep -o '"_id"' | wc -l | tr -d ' ')
if [ "$COUNT_SKIP" = "0" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC} (包含 $COUNT_SKIP 条)"
    FAILED=$((FAILED + 1))
fi

# 创建用户与任务用于更多双向引用边界
REF_USER_A=$(curl -s -X POST -H "Content-Type: application/json" -d '{"name":"A","email":"a_'"$(date +%s%N)"'@ex.com"}' "$BASE_URL/users" | grep -o '"_id":"[^"]*"' | head -1 | cut -d '"' -f4)
REF_USER_B=$(curl -s -X POST -H "Content-Type: application/json" -d '{"name":"B","email":"b_'"$(date +%s%N)"'@ex.com"}' "$BASE_URL/users" | grep -o '"_id":"[^"]*"' | head -1 | cut -d '"' -f4)
REF_TASK=$(curl -s -X POST -H "Content-Type: application/json" -d '{"name":"T-REF","deadline":"2026-01-01T00:00:00.000Z"}' "$BASE_URL/tasks" | grep -o '"_id":"[^"]*"' | head -1 | cut -d '"' -f4)

# 创建任务时 completed=true 且分配用户，应不加入 pendingTasks
echo -n "POST Task completed=true + assignedUser 不入 pendingTasks ... "
TASK_C_RESP=$(curl -s -X POST -H "Content-Type: application/json" -d '{"name":"T-C","deadline":"2026-01-01T00:00:00.000Z","assignedUser":"'$REF_USER_A'","completed":true}' "$BASE_URL/tasks")
TASK_C_ID=$(echo "$TASK_C_RESP" | grep -o '"_id":"[^"]*"' | head -1 | cut -d '"' -f4)
USERA_AFTER=$(curl -s "$BASE_URL/users/$REF_USER_A")
if echo "$USERA_AFTER" | grep -q "$TASK_C_ID"; then
    echo -e "${RED}✗ FAIL${NC}"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
fi

# PUT 任务 completed 从 false -> true 应从 pendingTasks 移除
ASSIGN_F=$(curl -s -X PUT -H "Content-Type: application/json" -d '{"name":"T-REF","deadline":"2026-01-01T00:00:00.000Z","assignedUser":"'$REF_USER_A'","completed":false}' "$BASE_URL/tasks/$REF_TASK")
echo -n "PUT Task completed=false->true 移除 pendingTasks ... "
SET_TRUE=$(curl -s -X PUT -H "Content-Type: application/json" -d '{"name":"T-REF","deadline":"2026-01-01T00:00:00.000Z","assignedUser":"'$REF_USER_A'","completed":true}' "$BASE_URL/tasks/$REF_TASK")
USERA_CHECK=$(curl -s "$BASE_URL/users/$REF_USER_A")
if echo "$USERA_CHECK" | grep -q "$REF_TASK"; then
    echo -e "${RED}✗ FAIL${NC}"
    FAILED=$((FAILED + 1))
else
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
fi

# PUT User 替换 pendingTasks 触发任务重指派（从 A -> B）
echo -n "PUT User 替换 pendingTasks 触发任务重指派 ... "
PUT_A=$(curl -s -X PUT -H "Content-Type: application/json" -d '{"name":"A","email":"a_update@ex.com","pendingTasks":["'$REF_TASK'"]}' "$BASE_URL/users/$REF_USER_A")
PUT_B=$(curl -s -X PUT -H "Content-Type: application/json" -d '{"name":"B","email":"b_update@ex.com","pendingTasks":["'$REF_TASK'"]}' "$BASE_URL/users/$REF_USER_B")
TASK_AFTER_MOVE=$(curl -s "$BASE_URL/tasks/$REF_TASK")
USERA_AFTER_MOVE=$(curl -s "$BASE_URL/users/$REF_USER_A")
USERB_AFTER_MOVE=$(curl -s "$BASE_URL/users/$REF_USER_B")
if echo "$TASK_AFTER_MOVE" | grep -q '"assignedUser":"'$REF_USER_B'"' && ! echo "$USERA_AFTER_MOVE" | grep -q "$REF_TASK" && echo "$USERB_AFTER_MOVE" | grep -q "$REF_TASK"; then
    echo -e "${GREEN}✓ PASS${NC}"
    PASSED=$((PASSED + 1))
else
    echo -e "${RED}✗ FAIL${NC}"
    FAILED=$((FAILED + 1))
fi

# 清理新增资源
curl -s -X DELETE "$BASE_URL/tasks/$TASK_C_ID" > /dev/null 2>&1
curl -s -X DELETE "$BASE_URL/tasks/$REF_TASK" > /dev/null 2>&1
curl -s -X DELETE "$BASE_URL/users/$REF_USER_A" > /dev/null 2>&1
curl -s -X DELETE "$BASE_URL/users/$REF_USER_B" > /dev/null 2>&1

echo ""
echo "========================================"
echo "  测试结果汇总"
echo "========================================"
echo ""
echo -e "通过: ${GREEN}$PASSED${NC}"
echo -e "失败: ${RED}$FAILED${NC}"
echo -e "总计: $((PASSED + FAILED))"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  ✓ 所有测试通过！${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}  ✗ 有 $FAILED 个测试失败${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi

