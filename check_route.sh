#!/bin/bash

# 检查是否已安装 nexttrace
is_installed=0
if ! command -v nexttrace &> /dev/null; then
  echo "nexttrace 未安装。正在安装 nexttrace..."
  is_installed=1
  curl nxtrace.org/nt | bash
fi

echo "测试结果只能说明您的IPV4到目标IP的路由表中没有跨网，不一定是接入了该线路，望周知"

# 定义IP地址和对应的AS号及线路名称
declare -A ip_as_map=(
  ["180.87.112.142"]="6453"
  ["203.131.243.153"]="2914"
  ["4.69.208.58"]="3356"
  ["184.104.220.67"]="6939"
  ["103.232.19.186"]="3257"
  ["63.216.84.146"]="3491"
  ["202.84.156.58"]="4637"
  ["62.115.165.87"]="1299"
  ["66.250.250.193"]="174"
  ["87.245.232.73"]="9002"
)

# 定义AS号和线路名称的映射
declare -A as_name_map=(
  ["6453"]="TATA"
  ["2914"]="NTT"
  ["3356"]="Level3"
  ["6939"]="HE"
  ["3257"]="GTT"
  ["3491"]="PCCW"
  ["4637"]="Telstra"
  ["1299"]="Telia"
  ["174"]="Cogent"
  ["9002"]="RETN"
)
# 定义存储结果的数组
declare -a valid_ips
declare -a invalid_ips

# 定义重试次数
max_retries=4

# 遍历IP地址并进行nexttrace检查
for ip in "${!ip_as_map[@]}"; do
  as_number="${ip_as_map[$ip]}"
  as_name="${as_name_map[$as_number]}"
  echo "检查 IP: $ip (AS$as_number - $as_name)"
  
  # 初始化变量
  all_checks_valid=true

  for check in {1..5}; do
    retry_count=0
    is_valid="yes"
    hop_count=0
    hkix_found=false
    equinix_found=false
    while [ $retry_count -lt $max_retries ]; do
      output=$(nexttrace $ip)
      
      # 检查输出是否包含错误信息
      if echo "$output" | grep -qE "Challenge does not exist|RetToken failed"; then
        echo "nexttrace 出现错误，正在重试... ($((retry_count + 1))/$max_retries)"
        ((retry_count++))
        sleep 1  # 等待一秒钟再重试
        continue
      fi
      
      # 初始化变量
      hop_count=0
      is_valid="yes"

      
      # 逐行解析输出
      while IFS= read -r line; do
        # 提取AS号 (假设每一行都有AS号并且格式为 AS<number>)
        hop_as=$(echo "$line" | grep -oE "AS[0-9]+")
        # 检查是否包含 HKIX
        if echo "$line" | grep -q -i "hkix"; then
          hkix_found=true
        fi
        # 检查是否包含 equinix
        if echo "$line" | grep -q -i "equinix"; then
          equinix_found=true
        fi
        # 如果提取到了AS号
        if [[ ! -z "$hop_as" ]]; then
          # 忽略第一跳
          ((hop_count++))
          if [[ $hop_count -eq 1 ]]; then
            continue
          fi
          
          # 检查AS号是否匹配
          hop_as_number="${hop_as:2}" # 去掉前缀 'AS'
          if [[ "$hop_as_number" != "$as_number" ]]; then
            is_valid="no"
            all_checks_valid=false
            break
          fi
        fi
      done <<< "$output"
      
      # 如果成功解析输出，则跳出重试循环
      break
    done
    
    if [ $retry_count -ge $max_retries ]; then
      echo "结果: 无法检查 $as_name (多次重试失败)"
      all_checks_valid=false
      break
    fi
    
    if [ "$is_valid" == "no" ]; then
      all_checks_valid=false
      break
    fi
  done

  if $all_checks_valid; then
    echo "结果: 到 $as_name 没有跨网"
    valid_ips+=("$ip ($as_name)")
  else
    echo "结果: 到 $as_name 存在跨网"
    invalid_ips+=("$ip ($as_name)")
  fi
  # 输出 HKIX 检查结果
  if $hkix_found; then
    echo " 到 $as_name 发现 HKIX 节点"
  fi
  # 输出 equinix 检查结果
  if $equinix_found; then
    echo " 到 $as_name 发现 equinix 节点"
  fi
done

# 输出统计结果
echo "统计结果:"
echo "未跨网的线路有:"
for valid_ip in "${valid_ips[@]}"; do
  echo "  $valid_ip"
done

echo "跨网的线路有:"
for invalid_ip in "${invalid_ips[@]}"; do
  echo "  $invalid_ip"
done

if [ "$is_installed" == "1" ]; then
  echo "正在卸载nexttrace..."
  rm -f /usr/local/bin/nexttrace
fi
