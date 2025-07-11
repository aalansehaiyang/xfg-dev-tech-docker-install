#!/bin/bash

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 输出带颜色的信息函数
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测操作系统类型
detect_os() {
    if [ -f /etc/redhat-release ]; then
        echo "centos"
    elif [ -f /etc/debian_version ]; then
        echo "ubuntu"
    else
        echo "unknown"
    fi
}

# 安装Docker的备选方案
install_docker_fallback() {
    local os_type=$(detect_os)
    
    warning "检测到Docker官方仓库连接失败，尝试使用备选安装方案..."
    
    case $os_type in
        "centos")
            install_docker_centos_fallback
            ;;
        "ubuntu")
            install_docker_ubuntu_fallback
            ;;
        *)
            error "不支持的操作系统类型，请手动安装Docker"
            ;;
    esac
}

# CentOS/RHEL备选安装方案
install_docker_centos_fallback() {
    info "使用CentOS备选方案安装Docker..."
    
    # 方案1: 使用阿里云镜像源
    info "尝试使用阿里云镜像源..."
    
    # 清理可能冲突的包
    sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
    
    # 安装依赖包
    sudo yum install -y yum-utils device-mapper-persistent-data lvm2
    
    # 添加阿里云Docker仓库
    sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    
    # 更新yum索引
    sudo yum makecache fast
    
    # 安装Docker CE
    if sudo yum install -y docker-ce docker-ce-cli containerd.io; then
        info "Docker安装成功（使用阿里云镜像源）"
        setup_docker_service
        return 0
    else
        warning "阿里云镜像源安装失败，尝试使用清华大学镜像源..."
        
        # 方案2: 使用清华大学镜像源
        sudo yum-config-manager --disable docker-ce-stable
        sudo yum-config-manager --add-repo https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/centos/docker-ce.repo
        
        if sudo yum install -y docker-ce docker-ce-cli containerd.io; then
            info "Docker安装成功（使用清华大学镜像源）"
            setup_docker_service
            return 0
        else
            warning "清华镜像源也失败，尝试使用系统默认仓库安装Docker..."
            
            # 方案3: 使用系统默认仓库的docker
            if sudo yum install -y docker; then
                info "Docker安装成功（使用系统默认仓库）"
                setup_docker_service
                return 0
            else
                error "所有安装方案都失败，请检查网络连接或手动安装Docker"
                return 1
            fi
        fi
    fi
}

# Ubuntu/Debian备选安装方案
install_docker_ubuntu_fallback() {
    info "使用Ubuntu备选方案安装Docker..."
    
    # 更新包索引
    sudo apt-get update
    
    # 安装依赖包
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # 方案1: 使用阿里云镜像源
    info "尝试使用阿里云镜像源..."
    
    # 添加阿里云Docker GPG密钥
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # 添加阿里云Docker仓库
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 更新包索引
    sudo apt-get update
    
    # 安装Docker CE
    if sudo apt-get install -y docker-ce docker-ce-cli containerd.io; then
        info "Docker安装成功（使用阿里云镜像源）"
        setup_docker_service
        return 0
    else
        warning "阿里云镜像源安装失败，尝试使用系统默认仓库..."
        
        # 方案2: 使用系统默认仓库
        if sudo apt-get install -y docker.io; then
            info "Docker安装成功（使用系统默认仓库）"
            setup_docker_service
            return 0
        else
            error "所有安装方案都失败，请检查网络连接或手动安装Docker"
            return 1
        fi
    fi
}

# 设置Docker服务
setup_docker_service() {
    info "配置Docker服务..."
    
    # 启动Docker服务
    sudo systemctl start docker
    
    # 设置开机自启
    sudo systemctl enable docker
    
    # 将当前用户添加到docker组（可选）
    if [ ! -z "$SUDO_USER" ]; then
        sudo usermod -aG docker $SUDO_USER
        info "用户 $SUDO_USER 已添加到docker组，注销后重新登录生效"
    elif [ ! -z "$USER" ]; then
        sudo usermod -aG docker $USER
        info "用户 $USER 已添加到docker组，注销后重新登录生效"
    fi
    
    # 配置Docker镜像加速器（使用阿里云）
    setup_docker_mirror
    
    # 验证Docker安装
    if docker --version > /dev/null 2>&1; then
        info "Docker安装验证成功"
        docker --version
    else
        warning "Docker安装可能有问题，请检查"
    fi
}

# 配置Docker镜像加速器
setup_docker_mirror() {
    info "配置Docker镜像加速器..."
    
    # 创建docker配置目录
    sudo mkdir -p /etc/docker
    
    # 配置镜像加速器
    cat <<EOF | sudo tee /etc/docker/daemon.json
{
    "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com",
        "https://hub-mirror.c.163.com",
        "https://mirrors.aliyun.com/docker-hub"
    ],
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "3"
    }
}
EOF
    
    # 重新加载配置并重启Docker
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    
    info "Docker镜像加速器配置完成"
}

# 定义下载URL和本地文件名
DOCKER_SCRIPT_URL="https://gitee.com/fustack/docker-install/releases/download/v1.2/install_docker_v1.2.sh"
LOCAL_SCRIPT_NAME="install_docker_v1.2.sh"

info "开始下载Docker安装脚本..."

# 下载Docker安装脚本
if curl -fsSL "$DOCKER_SCRIPT_URL" -o "$LOCAL_SCRIPT_NAME"; then
    info "下载完成: $LOCAL_SCRIPT_NAME"
else
    warning "下载失败，尝试使用备选安装方案"
    install_docker_fallback
    exit $?
fi

# 设置可执行权限
info "设置可执行权限..."
chmod +x "$LOCAL_SCRIPT_NAME"

# 执行安装脚本
info "开始执行Docker安装脚本..."
info "注意：安装过程可能需要root权限，如果需要会自动请求"
echo "-----------------------------------------------------------"
./$LOCAL_SCRIPT_NAME

# 检查安装脚本的退出状态
INSTALL_RESULT=$?

if [ $INSTALL_RESULT -eq 0 ]; then
    info "Docker安装脚本执行完成"
else
    warning "原始安装脚本执行失败，尝试使用备选安装方案..."
    install_docker_fallback
    INSTALL_RESULT=$?
fi

# 只有在Docker安装成功后才继续
if [ $INSTALL_RESULT -eq 0 ]; then
    # 询问用户是否安装Portainer
    read -p "是否安装Portainer容器管理界面？(y/n): " INSTALL_PORTAINER
    
    if [[ "$INSTALL_PORTAINER" =~ ^[Yy]$ ]]; then
        info "开始安装Portainer..."
        
        # 使用国内镜像源拉取Portainer
        if docker pull registry.cn-hangzhou.aliyuncs.com/portainer/portainer-ce:latest; then
            # 重新标记镜像
            docker tag registry.cn-hangzhou.aliyuncs.com/portainer/portainer-ce:latest portainer/portainer-ce:latest
            
            # 运行Portainer
            docker run -d --restart=always --name portainer -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer-ce:latest
        else
            # 如果国内镜像失败，尝试官方镜像
            docker run -d --restart=always --name portainer -p 9000:9000 -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer-ce:latest
        fi
        
        if [ $? -eq 0 ]; then
            info "Portainer安装成功！"
            warning "重要提示：请确保您的云服务器已开放9000端口！"
            echo "-----------------------------------------------------------"
            echo "Portainer访问方式："
            echo "1. 通过公网访问：http://您的服务器公网IP:9000"
            echo "2. 首次访问需要设置管理员账号和密码"
            echo "3. 登录后即可通过Web界面管理Docker容器"
            echo "-----------------------------------------------------------"
            info "您可以使用Portainer来方便地管理Docker容器、镜像、网络和卷等资源"
        else
            warning "Portainer安装失败，请手动安装或检查Docker状态"
        fi
    else
        info "用户选择不安装Portainer"
    fi
    
    # 清理下载的脚本文件
    if [ -f "$LOCAL_SCRIPT_NAME" ]; then
        rm -f "$LOCAL_SCRIPT_NAME"
        info "清理临时文件完成"
    fi
    
    echo "-----------------------------------------------------------"
    info "Docker安装完成！"
    warning "建议注销后重新登录以使docker组权限生效"
    echo "-----------------------------------------------------------"
else
    error "Docker安装失败，请查看上面的错误信息或手动安装"
fi
