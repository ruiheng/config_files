#!/bin/bash

# 启动带有 vertical-bufferline 的 nvim
# 使用方法：
# ./start-with-vbl.sh [nvim参数...]
# 或者：
# NVIM_ENABLE_VBL=1 nvim

export NVIM_ENABLE_VBL=1
nvim "$@"