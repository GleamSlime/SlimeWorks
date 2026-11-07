#!/usr/bin/env bash
# 一次性生成 macOS 稳定自签签名证书（本地跑，产物填进 GitHub Secrets）。
#
# 为什么要它：TCC 授权（完全磁盘访问、外置卷读取等）是按代码签名身份记的。
# CI 一直用 ad-hoc 签名，每次构建 CDHash 都变 → 每次自动更新后系统把这当成
# "另一个 App"，权限全部清零要重授。改用内容固定、可长期复用的自签证书后，
# 签名身份（证书锚点）跨版本不变，第一次授权之后更新不再掉权限。
#
# 需要填入的 Secrets（release.yml 的 build-macos job 读取）：
#   MAC_SIGN_IDENTITY_P12      = 导出的 signer.p12 的 base64（单行连续字符串）
#   MAC_SIGN_IDENTITY_PASSWORD = 导出时设置的 p12 口令
#   MAC_SIGN_IDENTITY_NAME     = 证书通用名（本脚本固定为 SlimeWorks Update Signer）
#
# 用法：bash scripts/make_mac_signing_cert.sh
# 注意：证书一旦生成并投入使用就不要再重新生成——换证书等于换身份，
# 用户机器上的 TCC 授权会全部重来。
set -euo pipefail

CN="SlimeWorks Update Signer"
OUT_DIR="mac_signing_cert"
mkdir -p "$OUT_DIR"
CERT_PEM="$OUT_DIR/signer.pem"
KEY_PEM="$OUT_DIR/signer.key"
P12="$OUT_DIR/signer.p12"

if [ -e "$P12" ]; then
  echo "❌ 已存在 $P12：重复生成会换掉证书身份，权限保持前功尽弃。确认要换新身份再手动删除后重跑。"
  exit 1
fi

echo "① 生成自签代码签名证书（有效期 10 年）"
cat > "$OUT_DIR/cert.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = sign_ext
[ dn ]
CN = $CN
[ sign_ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$KEY_PEM" -out "$CERT_PEM" \
  -days 3650 -config "$OUT_DIR/cert.cnf"

echo "② 打包 p12（CI 与本机都要用它签名）"
read -r -s -p "设置 p12 口令（GitHub Secret MAC_SIGN_IDENTITY_PASSWORD 用）: " P12_PASS; echo
read -r -s -p "再输一遍确认: " P12_PASS2; echo
if [ "$P12_PASS" != "$P12_PASS2" ]; then echo "❌ 两次口令不一致"; exit 1; fi
openssl pkcs12 -export -out "$P12" -inkey "$KEY_PEM" -in "$CERT_PEM" \
  -passout pass:"$P12_PASS" -name "$CN"

echo "③ 导入本机登录钥匙串并设为信任（可能弹系统授权框，请允许）"
security import "$P12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -T /usr/bin/codesign -P "$P12_PASS" || \
  echo "⚠️ 钥匙串导入失败：可双击 $P12 手动完成导入"
security add-trusted-cert -r trustRoot -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" "$CERT_PEM" 2>/dev/null || \
  echo '⚠️ 自动信任失败：请在"钥匙串访问"里找到该证书，右键 → Get Info → 信任 → 代码签名设为始终信任'

echo
echo "✅ 完成。GitHub Secrets 填法："
echo "   MAC_SIGN_IDENTITY_P12       <- base64 -i $P12 | tr -d '\n'"
echo "   MAC_SIGN_IDENTITY_PASSWORD  <- 刚才设置的口令"
echo "   MAC_SIGN_IDENTITY_NAME      <- $CN"
echo "注意：$P12 / $KEY_PEM 是敏感文件（仓库 .gitignore 已排除 *.p12/*.key/*.pem），切勿提交。"
