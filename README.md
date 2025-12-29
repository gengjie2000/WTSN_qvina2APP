---
title: "Untitled"
output: html_document
date: "2025-12-28"
---

# 高通量分子对接平台 (HTMD Web)

基于R Shiny和AutoDock Vina的在线分子对接平台。

## 功能特点

### 1. 蛋白质处理
- PDB文件上传与预处理
- 水分子和配体移除
- 3D结构可视化
- 氨基酸序列提取

### 2. 配体管理
- 支持多种格式：PDB, MOL2, SDF, PDBQT
- 批量上传处理
- 配体预处理与优化
- 格式自动转换

### 3. 对接参数设置
- 多种对接盒子设置策略：
  - 盲对接（自动计算质心）
  - 基于特定氨基酸
  - 自定义坐标
- 灵活的参数配置
- 实时3D可视化

### 4. 分子对接计算
- 单配体对接
- 批量高通量对接
- 虚拟筛选
- 作业队列管理
- 实时进度监控

### 5. 结果分析
- 结合能排序与筛选
- 构象聚类分析
- 相互作用可视化
- 多种格式导出

## 系统要求

### 软件依赖
1. R (>= 4.0.0)
2. R包依赖：
   - shiny, shinydashboard
   - bio3d (用于PDB文件处理)
   - plotly (用于可视化)
   - DT (数据表格)
   - future, promises (异步计算)

### 外部工具
1. AutoDock Vina (必须)
2. Open Babel (推荐，用于格式转换)
3. MGLTools (推荐，用于PDBQT生成)

## 安装部署

### 1. 本地部署
```bash
# 克隆仓库
git clone [repository-url]
cd htmdd-web

# 安装R包
install.packages(c("shiny", "shinydashboard", "bio3d", "plotly", 
                   "DT", "future", "promises", "httr", "jsonlite"))

# 安装AutoDock Vina
# 参考: http://vina.scripps.edu/download.html

# 运行应用
shiny::runApp("app.R")