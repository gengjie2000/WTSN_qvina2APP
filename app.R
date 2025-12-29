# 安装必要的包
# install.packages(c("shiny", "shinyFiles", "shinythemes", "shinycssloaders", 
#                   "dplyr", "readr", "stringr", "tidyr", "ggplot2", "fs", "DT"))

library(shiny)
library(shinyFiles)
library(shinythemes)
library(shinycssloaders)
library(dplyr)
library(readr)
library(stringr)
library(tidyr)
library(fs)
library(DT)

# 定义OpenBabel路径（根据您的设置）
openbabel_path <- "D:/autodocktools/OpenBabel-2.3.2"
obabel_exe <- file.path(openbabel_path, "obabel.exe")
babel_exe <- file.path(openbabel_path, "babel.exe")

# 检查使用哪个可执行文件
if (file.exists(obabel_exe)) {
  babel_cmd <- obabel_exe
} else if (file.exists(babel_exe)) {
  babel_cmd <- babel_exe
} else {
  babel_cmd <- "obabel"  # 如果不在指定路径，尝试系统PATH
}

# 定义MGLTools路径（仅用于蛋白质处理）
mgltools_path <- "D:/autodocktools"
python_path <- file.path(mgltools_path, "python.exe")
prepare_receptor <- file.path(mgltools_path, "Lib/site-packages/AutoDockTools/Utilities24/prepare_receptor4.py")

# 自定义函数获取Windows驱动器
getWindowsDrives <- function() {
  if (.Platform$OS.type == "windows") {
    tryCatch({
      # 使用系统命令获取驱动器列表
      drives <- system("wmic logicaldisk get name", intern = TRUE)
      drives <- drives[grep(":", drives)]
      drives <- gsub("\\s", "", drives)
      
      # 创建命名向量
      vol_names <- paste0(drives, "/")
      names(vol_names) <- drives
      
      # 添加常用路径
      vol_names <- c(
        "主目录" = path_home(),
        "R安装目录" = R.home(),
        vol_names
      )
      
      return(vol_names)
    }, error = function(e) {
      # 如果命令执行失败，返回默认路径
      return(c(
        "主目录" = path_home(),
        "R安装目录" = R.home(),
        "C盘" = "C:/",
        "D盘" = "D:/",
        "E盘" = "E:/",
        "F盘" = "F:/"
      ))
    })
  } else {
    # 对于非Windows系统
    return(c(
      "主目录" = path_home(),
      "R安装目录" = R.home(),
      "根目录" = "/"
    ))
  }
}

# 定义UI
ui <- fluidPage(
  theme = shinytheme("flatly"),
  
  titlePanel("Qvina2 分子对接平台"),
  
  sidebarLayout(
    sidebarPanel(
      width = 4,
      
      h4("1. 文件路径设置"),
      
      # Qvina2路径设置（可选）
      textInput("qvina2_path", "Qvina2路径 (可选):", 
                value = "",
                placeholder = "留空则使用系统PATH中的qvina2"),
      helpText("如果不确定，请留空。系统会自动查找Qvina2。"),
      
      # 输出目录选择
      shinyDirButton("output_dir", "选择输出目录", "请选择输出目录"),
      verbatimTextOutput("output_dir_path"),
      
      br(),
      h4("2. 蛋白质处理"),
      
      # 蛋白质文件上传
      fileInput("protein_file", "上传蛋白质PDB文件:",
                accept = c(".pdb")),
      
      # 蛋白质处理选项
      checkboxInput("skip_protein_check", "跳过蛋白质格式检查", value = TRUE),
      helpText("建议勾选，蛋白质PDBQT格式可能不同于标准格式"),
      
      br(),
      h4("3. 小分子处理"),
      
      # 小分子文件夹选择
      shinyDirButton("ligand_dir", "选择小分子文件夹", "请选择包含小分子文件的文件夹"),
      verbatimTextOutput("ligand_dir_path"),
      
      # 小分子文件类型选择
      radioButtons("ligand_format", "小分子文件格式:",
                   choices = c("PDB" = "pdb", "MOL2" = "mol2", "SDF" = "sdf", "SMILES" = "smi"),
                   selected = "pdb"),
      
      # OpenBabel路径设置（可选）
      textInput("openbabel_path", "OpenBabel路径 (可选):", 
                value = openbabel_path,
                placeholder = "留空则使用系统PATH中的obabel"),
      helpText("默认使用D:/autodocktools/OpenBabel-2.3.2，可修改"),
      
      # 小分子处理选项
      checkboxInput("add_hydrogens", "添加氢原子", value = TRUE),
      checkboxInput("gen3d", "生成3D坐标（仅SMILES）", value = TRUE),
      helpText("OpenBabel会自动处理小分子格式转换"),
      
      br(),
      h4("4. 对接参数设置"),
      
      # 对接参数
      numericInput("box_size", "盒子尺寸 (Å):", value = 40, min = 10, max = 100),
      numericInput("exhaustiveness", "搜索详尽度:", value = 8, min = 1, max = 32),
      numericInput("num_modes", "输出构象数:", value = 9, min = 1, max = 20),
      numericInput("energy_range", "能量范围:", value = 3, min = 0, max = 10),
      
      # 高级选项
      checkboxInput("fix_pdbqt", "自动修复PDBQT格式", value = TRUE),
      helpText("自动修复PDBQT文件中的格式问题"),
      
      # 开始对接按钮
      actionButton("run_docking", "开始分子对接", 
                   class = "btn-primary btn-lg btn-block",
                   icon = icon("play"))
    ),
    
    mainPanel(
      width = 8,
      tabsetPanel(
        tabPanel("处理进度",
                 h3("分子对接进度"),
                 br(),
                 
                 # Qvina2状态显示
                 uiOutput("qvina2_status"),
                 
                 # OpenBabel状态显示
                 uiOutput("openbabel_status"),
                 
                 # 进度条
                 fluidRow(
                   column(12,
                          h4("总体进度:"),
                          uiOutput("overall_progress"),
                          br(),
                          h4("当前任务:"),
                          uiOutput("current_task"),
                          br(),
                          h4("详细进度:"),
                          withSpinner(uiOutput("detailed_progress"), type = 4, color = "#0dc5c1")
                   )
                 ),
                 
                 # 实时日志
                 h4("处理日志:"),
                 div(style = "height:300px; overflow-y: scroll; border: 1px solid #ddd; padding: 10px;",
                     verbatimTextOutput("log_output")
                 ),
                 
                 # 结果显示
                 h4("对接结果汇总:"),
                 withSpinner(DT::dataTableOutput("results_table"), type = 4, color = "#0dc5c1")
        ),
        
        tabPanel("参数配置",
                 h3("配置文件预览"),
                 br(),
                 
                 # 盒子中心计算
                 h4("蛋白质信息:"),
                 verbatimTextOutput("protein_info"),
                 
                 h4("对接配置文件示例:"),
                 verbatimTextOutput("config_preview")
        ),
        
        tabPanel("结果可视化",
                 h3("结合能分布"),
                 br(),
                 
                 plotOutput("energy_plot", height = "400px"),
                 
                 br(),
                 h4("结合能统计:"),
                 tableOutput("energy_stats")
        ),
        
        tabPanel("帮助文档",
                 h3("使用说明"),
                 br(),
                 
                 h4("1. 准备工作:"),
                 tags$ul(
                   tags$li("确保已安装AutoDockTools（用于蛋白质处理）"),
                   tags$li("确保已安装OpenBabel（用于小分子处理）"),
                   tags$li("确保已安装Qvina2"),
                   tags$li("MGLTools路径已正确设置: ", code(mgltools_path)),
                   tags$li("OpenBabel路径: ", code(openbabel_path)),
                   tags$li("Qvina2已添加到系统PATH环境变量，或在下方指定路径"),
                   tags$li("准备蛋白质PDB文件和小分子文件夹")
                 ),
                 
                 h4("2. 文件要求:"),
                 tags$ul(
                   tags$li("蛋白质文件: 标准的PDB格式"),
                   tags$li("小分子文件: PDB、MOL2、SDF或SMILES格式"),
                   tags$li("OpenBabel支持多种小分子格式转换"),
                   tags$li("小分子文件夹内只包含小分子文件")
                 ),
                 
                 h4("3. 对接流程:"),
                 tags$ol(
                   tags$li("上传蛋白质PDB文件"),
                   tags$li("选择包含小分子的文件夹"),
                   tags$li("选择小分子文件格式"),
                   tags$li("设置对接参数（盒子大小、搜索详尽度等）"),
                   tags$li("勾选'添加氢原子'选项（推荐）"),
                   tags$li("点击'开始分子对接'按钮"),
                   tags$li("在'处理进度'标签页查看实时进度")
                 ),
                 
                 h4("4. 输出文件:"),
                 tags$ul(
                   tags$li("处理后的蛋白质文件: receptor.pdbqt"),
                   tags$li("处理后的配体文件: 每个小分子生成对应的.pdbqt文件"),
                   tags$li("对接结果: 每个小分子生成对接后的.pdbqt文件"),
                   tags$li("配置文件: 每个小分子生成对应的config.txt文件"),
                   tags$li("结果汇总: docking_results.csv")
                 ),
                 
                 h4("5. 常见问题:"),
                 tags$ul(
                   tags$li("如果遇到'ATOM syntax incorrect'错误，请勾选'自动修复PDBQT格式'"),
                   tags$li("PDBQT格式问题通常是由于坐标字段格式不正确"),
                   tags$li("自动修复功能会调整PDBQT文件的格式以满足Qvina2的要求"),
                   tags$li("OpenBabel通常能更好地处理小分子格式转换"),
                   tags$li("如果SMILES文件转换失败，请勾选'生成3D坐标'")
                 )
        )
      )
    )
  )
)

# 定义服务器逻辑
server <- function(input, output, session) {
  # 设置文件系统访问权限 - 使用自定义函数
  volumes <- getWindowsDrives()
  
  # 初始化变量
  values <- reactiveValues(
    progress = list(
      total = 0,
      current = 0,
      success = 0,
      failed = 0,
      status = "准备就绪",
      current_ligand = "",
      overall_percent = 0
    ),
    log = c(),
    results = data.frame(),
    protein_center = c(0, 0, 0),
    qvina2_found = FALSE,
    qvina2_path = "",
    openbabel_found = FALSE,
    openbabel_path = ""
  )
  
  # 选择输出目录
  shinyDirChoose(input, "output_dir", roots = volumes, session = session)
  
  output$output_dir_path <- renderText({
    if (!is.integer(input$output_dir)) {
      path <- parseDirPath(volumes, input$output_dir)
      return(path)
    }
    return("未选择输出目录")
  })
  
  # 选择小分子文件夹
  shinyDirChoose(input, "ligand_dir", roots = volumes, session = session)
  
  output$ligand_dir_path <- renderText({
    if (!is.integer(input$ligand_dir)) {
      path <- parseDirPath(volumes, input$ligand_dir)
      return(path)
    }
    return("未选择小分子文件夹")
  })
  
  # 添加日志信息
  add_log <- function(message) {
    timestamp <- format(Sys.time(), "%H:%M:%S")
    log_entry <- paste("[", timestamp, "] ", message, sep = "")
    values$log <- c(values$log, log_entry)
    output$log_output <- renderText({
      paste(values$log, collapse = "\n")
    })
  }
  
  # 更新进度
  update_progress <- function(total, current, success, failed, status, current_ligand = "") {
    values$progress$total <- total
    values$progress$current <- current
    values$progress$success <- success
    values$progress$failed <- failed
    values$progress$status <- status
    values$progress$current_ligand <- current_ligand
    values$progress$overall_percent <- ifelse(total > 0, round(current / total * 100), 0)
  }
  
  # 显示Qvina2状态
  output$qvina2_status <- renderUI({
    if (input$qvina2_path != "") {
      # 如果用户指定了路径，检查该路径
      if (file.exists(input$qvina2_path)) {
        # 测试文件是否可执行
        test_cmd <- paste(shQuote(input$qvina2_path), "--help")
        tryCatch({
          result <- system(test_cmd, intern = TRUE, ignore.stderr = TRUE, timeout = 2)
          if (length(result) > 0) {
            values$qvina2_found <- TRUE
            values$qvina2_path <- input$qvina2_path
            return(tags$div(class = "alert alert-success",
                            icon("check-circle"), " Qvina2路径有效: ", input$qvina2_path))
          } else {
            values$qvina2_found <- FALSE
            return(tags$div(class = "alert alert-warning",
                            icon("exclamation-triangle"), " 无法验证Qvina2程序"))
          }
        }, error = function(e) {
          values$qvina2_found <- FALSE
          return(tags$div(class = "alert alert-warning",
                          icon("exclamation-triangle"), " Qvina2验证失败: ", e$message))
        })
      } else {
        values$qvina2_found <- FALSE
        return(tags$div(class = "alert alert-danger",
                        icon("exclamation-triangle"), " Qvina2未找到: ", input$qvina2_path))
      }
    } else {
      # 如果用户未指定路径，尝试在系统PATH中查找
      tryCatch({
        # 方法1: 尝试直接运行qvina2 --help
        result <- system("qvina2 --help", intern = TRUE, ignore.stderr = TRUE, timeout = 2)
        if (length(result) > 0) {
          values$qvina2_found <- TRUE
          values$qvina2_path <- "qvina2"
          return(tags$div(class = "alert alert-success",
                          icon("check-circle"), " Qvina2已找到 (系统PATH)"))
        } else {
          # 方法2: 尝试查找常见路径
          common_paths <- c(
            "C:/Program Files/Qvina2/qvina2.exe",
            "C:/Program Files (x86)/Qvina2/qvina2.exe",
            "D:/Qvina2/qvina2.exe",
            "D:/vina/qvina2.exe",
            "/usr/local/bin/qvina2",
            "/usr/bin/qvina2"
          )
          
          for (path in common_paths) {
            if (file.exists(path)) {
              values$qvina2_found <- TRUE
              values$qvina2_path <- path
              return(tags$div(class = "alert alert-success",
                              icon("check-circle"), " Qvina2已找到: ", path))
            }
          }
          
          values$qvina2_found <- FALSE
          return(tags$div(class = "alert alert-warning",
                          icon("exclamation-triangle"), 
                          " 未在系统PATH中找到Qvina2。请在左侧输入完整路径，或确保已添加到系统PATH。"))
        }
      }, error = function(e) {
        values$qvina2_found <- FALSE
        return(tags$div(class = "alert alert-warning",
                        icon("exclamation-triangle"), 
                        " 检查Qvina2时出错: ", e$message))
      })
    }
  })
  
  # 显示OpenBabel状态
  output$openbabel_status <- renderUI({
    # 确定要使用的路径
    ob_path <- ifelse(input$openbabel_path != "", input$openbabel_path, openbabel_path)
    
    # 检查OpenBabel是否可用
    if (ob_path != "") {
      # 尝试找到obabel或babel可执行文件
      possible_exes <- c(
        file.path(ob_path, "obabel.exe"),
        file.path(ob_path, "babel.exe"),
        file.path(ob_path, "bin/obabel.exe"),
        file.path(ob_path, "bin/babel.exe")
      )
      
      found_exe <- NULL
      for (exe in possible_exes) {
        if (file.exists(exe)) {
          found_exe <- exe
          break
        }
      }
      
      # 如果找不到，尝试系统PATH
      if (is.null(found_exe)) {
        tryCatch({
          result <- system("obabel --help", intern = TRUE, ignore.stderr = TRUE, timeout = 2)
          if (length(result) > 0) {
            values$openbabel_found <- TRUE
            values$openbabel_path <- "obabel"
            return(tags$div(class = "alert alert-success",
                            icon("check-circle"), " OpenBabel已找到 (系统PATH)"))
          }
        }, error = function(e) {
          # 继续检查其他方法
        })
        
        tryCatch({
          result <- system("babel --help", intern = TRUE, ignore.stderr = TRUE, timeout = 2)
          if (length(result) > 0) {
            values$openbabel_found <- TRUE
            values$openbabel_path <- "babel"
            return(tags$div(class = "alert alert-success",
                            icon("check-circle"), " OpenBabel已找到 (系统PATH，命令: babel)"))
          }
        }, error = function(e) {
          # 继续检查其他方法
        })
        
        values$openbabel_found <- FALSE
        return(tags$div(class = "alert alert-danger",
                        icon("exclamation-triangle"), " OpenBabel未找到。请检查路径或安装OpenBabel。"))
      } else {
        # 测试找到的可执行文件
        test_cmd <- paste(shQuote(found_exe), "--help")
        tryCatch({
          result <- system(test_cmd, intern = TRUE, ignore.stderr = TRUE, timeout = 2)
          if (length(result) > 0) {
            values$openbabel_found <- TRUE
            values$openbabel_path <- found_exe
            return(tags$div(class = "alert alert-success",
                            icon("check-circle"), " OpenBabel已找到: ", found_exe))
          } else {
            values$openbabel_found <- FALSE
            return(tags$div(class = "alert alert-warning",
                            icon("exclamation-triangle"), " 无法验证OpenBabel程序"))
          }
        }, error = function(e) {
          values$openbabel_found <- FALSE
          return(tags$div(class = "alert alert-warning",
                          icon("exclamation-triangle"), " OpenBabel验证失败: ", e$message))
        })
      }
    } else {
      # 如果路径为空，尝试系统PATH
      tryCatch({
        result <- system("obabel --help", intern = TRUE, ignore.stderr = TRUE, timeout = 2)
        if (length(result) > 0) {
          values$openbabel_found <- TRUE
          values$openbabel_path <- "obabel"
          return(tags$div(class = "alert alert-success",
                          icon("check-circle"), " OpenBabel已找到 (系统PATH)"))
        } else {
          values$openbabel_found <- FALSE
          return(tags$div(class = "alert alert-warning",
                          icon("exclamation-triangle"), " 未在系统PATH中找到OpenBabel"))
        }
      }, error = function(e) {
        values$openbabel_found <- FALSE
        return(tags$div(class = "alert alert-warning",
                        icon("exclamation-triangle"), " 检查OpenBabel时出错: ", e$message))
      })
    }
  })
  
  # 显示总体进度条
  output$overall_progress <- renderUI({
    tagList(
      tags$div(
        class = "progress",
        tags$div(
          class = "progress-bar progress-bar-striped active",
          role = "progressbar",
          style = paste0("width:", values$progress$overall_percent, "%;"),
          paste0(values$progress$overall_percent, "%")
        )
      ),
      tags$p(paste0("已完成: ", values$progress$current, "/", values$progress$total, 
                    " (成功: ", values$progress$success, ", 失败: ", values$progress$failed, ")"))
    )
  })
  
  # 显示当前任务
  output$current_task <- renderUI({
    tagList(
      tags$div(
        class = "alert alert-info",
        paste0("状态: ", values$progress$status)
      ),
      if (values$progress$current_ligand != "") {
        tags$div(
          class = "alert alert-warning",
          paste0("当前处理: ", values$progress$current_ligand)
        )
      }
    )
  })
  
  # 显示详细进度
  output$detailed_progress <- renderUI({
    if (values$progress$total > 0) {
      tagList(
        tags$h5("进度详情:"),
        tags$ul(
          tags$li(paste("总任务数:", values$progress$total)),
          tags$li(paste("当前进度:", values$progress$current, "/", values$progress$total)),
          tags$li(paste("成功:", values$progress$success)),
          tags$li(paste("失败:", values$progress$failed))
        )
      )
    } else {
      tags$div(
        class = "alert alert-info",
        "准备开始对接，请点击'开始分子对接'按钮"
      )
    }
  })
  
  # 检查Qvina2是否可用
  check_qvina2 <- function() {
    add_log("检查Qvina2是否可用...")
    
    if (input$qvina2_path != "") {
      # 使用用户指定的路径
      qvina_path <- input$qvina2_path
      if (!file.exists(qvina_path)) {
        add_log(paste("错误: 指定的Qvina2路径不存在:", qvina_path))
        return(FALSE)
      }
      
      # 测试Qvina2
      test_cmd <- paste(shQuote(qvina_path), "--help")
      tryCatch({
        result <- system(test_cmd, intern = TRUE, ignore.stderr = TRUE, timeout = 5)
        if (length(result) > 0) {
          add_log(paste("✓ Qvina2检测成功:", qvina_path))
          values$qvina2_path <- qvina_path
          return(TRUE)
        } else {
          add_log("⚠ Qvina2可能不是有效版本")
          return(FALSE)
        }
      }, error = function(e) {
        add_log(paste("✗ 无法运行Qvina2:", e$message))
        return(FALSE)
      })
    } else {
      # 尝试在系统PATH中查找
      tryCatch({
        # 方法1: 直接运行
        result <- system("qvina2 --help", intern = TRUE, ignore.stderr = TRUE, timeout = 5)
        if (length(result) > 0) {
          add_log("✓ Qvina2检测成功 (系统PATH)")
          values$qvina2_path <- "qvina2"
          return(TRUE)
        } else {
          # 方法2: 尝试不同命令变体
          commands <- c("qvina2", "qvina2.exe", "Qvina2", "Qvina2.exe")
          
          for (cmd in commands) {
            tryCatch({
              test_result <- system(paste(cmd, "--help"), intern = TRUE, 
                                    ignore.stderr = TRUE, timeout = 2)
              if (length(test_result) > 0) {
                add_log(paste("✓ Qvina2检测成功 (命令:", cmd, ")"))
                values$qvina2_path <- cmd
                return(TRUE)
              }
            }, error = function(e) {
              # 继续尝试下一个命令
            })
          }
          
          add_log("✗ 未在系统PATH中找到Qvina2")
          add_log("请确保Qvina2已添加到系统PATH，或在左侧输入完整路径")
          return(FALSE)
        }
      }, error = function(e) {
        add_log(paste("✗ 检查Qvina2时出错:", e$message))
        return(FALSE)
      })
    }
  }
  
  # 检查OpenBabel是否可用
  check_openbabel <- function() {
    add_log("检查OpenBabel是否可用...")
    
    # 确定要使用的路径
    ob_path <- ifelse(input$openbabel_path != "", input$openbabel_path, openbabel_path)
    
    if (ob_path != "") {
      # 尝试找到obabel或babel可执行文件
      possible_exes <- c(
        file.path(ob_path, "obabel.exe"),
        file.path(ob_path, "babel.exe"),
        file.path(ob_path, "bin/obabel.exe"),
        file.path(ob_path, "bin/babel.exe")
      )
      
      found_exe <- NULL
      for (exe in possible_exes) {
        if (file.exists(exe)) {
          found_exe <- exe
          break
        }
      }
      
      if (!is.null(found_exe)) {
        # 测试OpenBabel
        test_cmd <- paste(shQuote(found_exe), "--help")
        tryCatch({
          result <- system(test_cmd, intern = TRUE, ignore.stderr = TRUE, timeout = 5)
          if (length(result) > 0) {
            add_log(paste("✓ OpenBabel检测成功:", found_exe))
            values$openbabel_path <- found_exe
            return(TRUE)
          } else {
            add_log("⚠ OpenBabel可能不是有效版本")
            return(FALSE)
          }
        }, error = function(e) {
          add_log(paste("✗ 无法运行OpenBabel:", e$message))
          return(FALSE)
        })
      } else {
        add_log(paste("✗ 在指定路径未找到OpenBabel可执行文件:", ob_path))
      }
    }
    
    # 如果指定路径未找到，尝试系统PATH
    tryCatch({
      # 尝试obabel命令
      result <- system("obabel --help", intern = TRUE, ignore.stderr = TRUE, timeout = 5)
      if (length(result) > 0) {
        add_log("✓ OpenBabel检测成功 (系统PATH，命令: obabel)")
        values$openbabel_path <- "obabel"
        return(TRUE)
      }
    }, error = function(e) {
      # 继续尝试babel命令
    })
    
    tryCatch({
      # 尝试babel命令
      result <- system("babel --help", intern = TRUE, ignore.stderr = TRUE, timeout = 5)
      if (length(result) > 0) {
        add_log("✓ OpenBabel检测成功 (系统PATH，命令: babel)")
        values$openbabel_path <- "babel"
        return(TRUE)
      }
    }, error = function(e) {
      # 继续尝试其他方法
    })
    
    add_log("✗ 未找到OpenBabel")
    add_log("请确保OpenBabel已安装，并在左侧输入正确路径，或已添加到系统PATH")
    return(FALSE)
  }
  
  # 计算蛋白质中心
  calculate_protein_center <- function(pdb_file) {
    tryCatch({
      # 读取PDB文件并提取坐标
      pdb_lines <- readLines(pdb_file)
      atom_lines <- pdb_lines[grepl("^ATOM", pdb_lines)]
      
      if (length(atom_lines) == 0) {
        return(c(0, 0, 0))
      }
      
      # 提取坐标
      coords <- sapply(atom_lines, function(line) {
        x <- as.numeric(substr(line, 31, 38))
        y <- as.numeric(substr(line, 39, 46))
        z <- as.numeric(substr(line, 47, 54))
        c(x, y, z)
      })
      
      # 计算中心
      center <- rowMeans(coords)
      return(round(center, 3))
      
    }, error = function(e) {
      add_log(paste("计算蛋白质中心时出错:", e$message))
      return(c(0, 0, 0))
    })
  }
  
  # 修复PDBQT文件格式
  fix_pdbqt_file <- function(pdbqt_file) {
    tryCatch({
      # 读取文件
      lines <- readLines(pdbqt_file, warn = FALSE)
      fixed_lines <- character(0)
      changes_made <- FALSE
      
      for (i in 1:length(lines)) {
        line <- lines[i]
        
        # 如果是ATOM或HETATM记录
        if (grepl("^(ATOM|HETATM)", line)) {
          # 检查行长度
          if (nchar(line) < 80) {
            # 填充到至少80字符
            line <- paste0(line, strrep(" ", 80 - nchar(line)))
            changes_made <- TRUE
          }
          
          # 检查坐标格式（位置31-54）
          if (nchar(line) >= 54) {
            x_str <- substr(line, 31, 38)
            y_str <- substr(line, 39, 46)
            z_str <- substr(line, 47, 54)
            
            # 确保坐标是数字并且有正确的格式
            tryCatch({
              x <- as.numeric(x_str)
              y <- as.numeric(y_str)
              z <- as.numeric(z_str)
              
              # 格式化为8.3格式（总宽度8，小数点后3位）
              x_fmt <- sprintf("%8.3f", x)
              y_fmt <- sprintf("%8.3f", y)
              z_fmt <- sprintf("%8.3f", z)
              
              # 如果格式不同，替换坐标部分
              if (x_str != x_fmt || y_str != y_fmt || z_str != z_fmt) {
                line <- paste0(substr(line, 1, 30), x_fmt, y_fmt, z_fmt, substr(line, 55, nchar(line)))
                changes_made <- TRUE
              }
            }, error = function(e) {
              # 坐标不是数字，尝试修复
              add_log(paste("警告: 第", i, "行坐标格式错误:", e$message))
            })
          }
        }
        
        fixed_lines <- c(fixed_lines, line)
      }
      
      # 如果有修改，写回文件
      if (changes_made) {
        # 备份原文件
        backup_file <- paste0(pdbqt_file, ".backup")
        file.copy(pdbqt_file, backup_file, overwrite = TRUE)
        
        # 写入修复后的文件
        writeLines(fixed_lines, pdbqt_file, useBytes = TRUE)
        add_log(paste("已修复PDBQT文件格式:", pdbqt_file, "(备份:", backup_file, ")"))
        return(TRUE)
      } else {
        add_log(paste("PDBQT文件格式正常，无需修复:", pdbqt_file))
        return(TRUE)
      }
    }, error = function(e) {
      add_log(paste("修复PDBQT文件时出错:", e$message))
      return(FALSE)
    })
  }
  
  # 处理蛋白质
  process_protein <- function(pdb_file, output_dir) {
    add_log("开始处理蛋白质文件...")
    update_progress(0, 0, 0, 0, "处理蛋白质中...", "")
    
    # 生成输出文件名
    output_file <- file.path(output_dir, "receptor.pdbqt")
    
    # 构建命令
    cmd <- paste(
      shQuote(python_path),
      shQuote(prepare_receptor),
      "-r", shQuote(pdb_file),
      "-o", shQuote(output_file),
      "-A", "checkhydrogens",
      "-U", "nphs_lps_waters_nonstdres"
    )
    
    add_log(paste("执行蛋白质处理命令:", cmd))
    
    # 执行命令
    result <- system(cmd, intern = TRUE, ignore.stderr = FALSE)
    
    if (any(grepl("error|Error|ERROR", result, ignore.case = TRUE))) {
      add_log(paste("蛋白质处理警告:", paste(result, collapse = "\n")))
    }
    
    if (file.exists(output_file)) {
      # 如果启用自动修复，尝试修复PDBQT格式
      if (input$fix_pdbqt) {
        fix_pdbqt_file(output_file)
      }
      
      add_log(paste("蛋白质处理完成:", output_file))
      return(TRUE)
    } else {
      add_log("蛋白质处理失败，未生成输出文件")
      return(FALSE)
    }
  }
  
  # 使用OpenBabel处理小分子
  process_ligand_openbabel <- function(ligand_file, output_dir, index, total) {
    ligand_name <- tools::file_path_sans_ext(basename(ligand_file))
    add_log(paste("处理小分子", index, "/", total, ":", ligand_name))
    update_progress(total, index, values$progress$success, values$progress$failed, 
                    "处理小分子中...", ligand_name)
    
    # 生成输出文件名
    base_name <- tools::file_path_sans_ext(basename(ligand_file))
    output_file <- file.path(output_dir, "ligands", paste0(base_name, ".pdbqt"))
    
    # 创建输出目录
    dir.create(file.path(output_dir, "ligands"), showWarnings = FALSE, recursive = TRUE)
    
    # 先检查输入文件是否有效
    if (!file.exists(ligand_file)) {
      add_log(paste("错误: 小分子文件不存在:", ligand_file))
      return(list(success = FALSE, file = NULL, name = base_name, message = "文件不存在"))
    }
    
    # 确定输入格式
    input_format <- tolower(input$ligand_format)
    
    # 构建OpenBabel命令
    # 基本命令：转换格式并添加氢原子
    cmd_parts <- c(shQuote(values$openbabel_path))
    
    # 输入文件
    cmd_parts <- c(cmd_parts, paste0("-i", input_format), shQuote(ligand_file))
    
    # 输出格式
    cmd_parts <- c(cmd_parts, "-opdbqt", "-O", shQuote(output_file))
    
    # 添加氢原子（如果选项启用）
    if (input$add_hydrogens) {
      cmd_parts <- c(cmd_parts, "-h")
    }
    
    # 对于SMILES文件，可能需要生成3D坐标
    if (input_format == "smi" && input$gen3d) {
      cmd_parts <- c(cmd_parts, "--gen3d")
    }
    
    # 添加其他参数：计算Gasteiger电荷（AutoDock需要）
    cmd_parts <- c(cmd_parts, "--partialcharge", "gasteiger")
    
    # 完整命令
    cmd <- paste(cmd_parts, collapse = " ")
    
    add_log(paste("执行OpenBabel命令:", cmd))
    
    # 执行命令
    tryCatch({
      result <- system(cmd, intern = TRUE, ignore.stderr = FALSE)
      
      # 检查是否有错误信息
      if (any(grepl("error|Error|ERROR|Cannot|not", result, ignore.case = TRUE))) {
        add_log(paste("OpenBabel警告:", paste(result, collapse = "\n")))
      }
      
      if (file.exists(output_file)) {
        # 检查文件是否为空
        file_info <- file.info(output_file)
        if (file_info$size == 0) {
          add_log(paste("错误: 生成的PDBQT文件为空:", output_file))
          return(list(success = FALSE, file = NULL, name = base_name, message = "生成的PDBQT文件为空"))
        }
        
        # 如果启用自动修复，尝试修复PDBQT格式
        if (input$fix_pdbqt) {
          fix_success <- fix_pdbqt_file(output_file)
          if (!fix_success) {
            add_log("PDBQT文件修复失败，但将继续使用原文件")
          }
        }
        
        add_log(paste("小分子处理成功:", output_file))
        return(list(success = TRUE, file = output_file, name = base_name, message = "成功"))
      } else {
        add_log(paste("小分子处理失败，未生成输出文件。命令输出:", paste(result, collapse = "\n")))
        return(list(success = FALSE, file = NULL, name = base_name, message = "未生成输出文件"))
      }
    }, error = function(e) {
      add_log(paste("处理小分子时出错:", e$message))
      return(list(success = FALSE, file = NULL, name = base_name, message = e$message))
    })
  }
  
  # 创建配置文件
  create_config_file <- function(protein_file, ligand_file, output_dir, ligand_name) {
    config_file <- file.path(output_dir, "configs", paste0(ligand_name, "_config.txt"))
    dir.create(file.path(output_dir, "configs"), showWarnings = FALSE, recursive = TRUE)
    
    # 计算盒子中心（使用之前计算的蛋白质中心）
    center_x <- values$protein_center[1]
    center_y <- values$protein_center[2]
    center_z <- values$protein_center[3]
    
    # 创建配置文件内容 - 完整格式
    config_content <- paste(
      "# Qvina2 configuration file for ligand:", ligand_name,
      "\nreceptor = ", protein_file,
      "\nligand = ", ligand_file,
      "\n\n# Center of the search space (Angstrom)",
      "\ncenter_x = ", center_x,
      "\ncenter_y = ", center_y,
      "\ncenter_z = ", center_z,
      "\n\n# Size of the search space (Angstrom)",
      "\nsize_x = ", input$box_size,
      "\nsize_y = ", input$box_size,
      "\nsize_z = ", input$box_size,
      "\n\n# Exhaustiveness of the search",
      "\nexhaustiveness = ", input$exhaustiveness,
      "\n\n# Number of binding modes to generate",
      "\nnum_modes = ", input$num_modes,
      "\n\n# Maximum energy difference between the best binding mode and the worst one displayed (kcal/mol)",
      "\nenergy_range = ", input$energy_range,
      sep = ""
    )
    
    # 写入配置文件
    writeLines(config_content, config_file, useBytes = TRUE)
    
    add_log(paste("创建配置文件:", config_file))
    return(config_file)
  }
  
  # 执行对接 - 使用Qvina2
  run_docking <- function(config_file, ligand_name, output_dir, ligand_pdbqt, index, total) {
    add_log(paste("开始对接小分子", index, "/", total, ":", ligand_name))
    update_progress(total, index, values$progress$success, values$progress$failed, 
                    "运行对接中...", ligand_name)
    
    # 首先检查ligand_pdbqt文件是否存在
    if (!file.exists(ligand_pdbqt)) {
      add_log(paste("错误: 配体PDBQT文件不存在:", ligand_pdbqt))
      return(list(success = FALSE, energy = NA, all_energies = numeric(0), message = "配体文件不存在"))
    }
    
    # 准备输出文件路径
    log_file <- file.path(output_dir, "logs", paste0(ligand_name, ".txt"))
    out_file <- file.path(output_dir, "results", paste0(ligand_name, "_docked.pdbqt"))
    
    # 创建目录
    dir.create(file.path(output_dir, "logs"), showWarnings = FALSE, recursive = TRUE)
    dir.create(file.path(output_dir, "results"), showWarnings = FALSE, recursive = TRUE)
    
    # 构建Qvina2对接命令
    qvina_cmd <- values$qvina2_path
    
    # 构建完整命令
    cmd <- paste(
      shQuote(qvina_cmd),
      "--config", shQuote(config_file),
      "--log", shQuote(log_file),
      "--out", shQuote(out_file),
      "--exhaustiveness", input$exhaustiveness
    )
    
    # 添加可选参数
    if (!is.na(input$num_modes) && input$num_modes > 0) {
      cmd <- paste(cmd, "--num_modes", input$num_modes)
    }
    
    if (!is.na(input$energy_range) && input$energy_range > 0) {
      cmd <- paste(cmd, "--energy_range", input$energy_range)
    }
    
    add_log(paste("执行对接命令:", cmd))
    
    # 执行命令
    tryCatch({
      result <- system(cmd, intern = TRUE, ignore.stderr = FALSE)
      
      # 检查是否有错误信息
      error_lines <- result[grepl("error|Error|ERROR|Parse error", result, ignore.case = TRUE)]
      if (length(error_lines) > 0) {
        add_log(paste("Qvina2错误信息:", paste(error_lines, collapse = "\n")))
      }
      
      # 检查命令执行状态
      status <- attr(result, "status")
      if (!is.null(status) && status != 0) {
        add_log(paste("Qvina2执行失败，错误码:", status))
        return(list(success = FALSE, energy = NA, all_energies = numeric(0), message = paste("错误码:", status)))
      }
      
      # 从日志文件中提取结合能
      if (file.exists(log_file)) {
        tryCatch({
          log_content <- readLines(log_file, warn = FALSE)
          energies <- numeric(0)
          
          # 寻找能量行（Qvina2的输出格式）
          for (line in log_content) {
            # 匹配格式: "   1    -8.1      0.000" 或 "mode |   affinity | dist from best mode"
            if (grepl("^\\s+\\d+\\s+-?\\d+\\.\\d+\\s+", line)) {
              parts <- strsplit(trimws(line), "\\s+")[[1]]
              if (length(parts) >= 2 && grepl("-?\\d+\\.\\d+", parts[2])) {
                energy <- as.numeric(parts[2])
                energies <- c(energies, energy)
              }
            }
          }
          
          if (length(energies) > 0) {
            best_energy <- min(energies)
            add_log(paste("对接成功! 最佳结合能:", best_energy, "kcal/mol"))
            return(list(success = TRUE, energy = best_energy, all_energies = energies, message = "成功"))
          }
        }, error = function(e) {
          add_log(paste("读取日志文件时出错:", e$message))
        })
      }
      
      # 检查输出文件是否存在
      if (file.exists(out_file)) {
        add_log("对接完成，但未找到能量信息")
        return(list(success = TRUE, energy = NA, all_energies = numeric(0), message = "完成但无能量信息"))
      } else {
        add_log("对接失败，未生成输出文件")
        return(list(success = FALSE, energy = NA, all_energies = numeric(0), message = "未生成输出文件"))
      }
    }, error = function(e) {
      add_log(paste("对接执行出错:", e$message))
      return(list(success = FALSE, energy = NA, all_energies = numeric(0), message = e$message))
    })
  }
  
  # 主对接函数
  run_docking_pipeline <- function() {
    # 获取输出目录
    output_dir <- parseDirPath(volumes, input$output_dir)
    
    # 检查必要的输入
    if (is.null(input$protein_file)) {
      add_log("错误: 请上传蛋白质文件")
      return()
    }
    
    if (is.integer(input$ligand_dir)) {
      add_log("错误: 请选择小分子文件夹")
      return()
    }
    
    if (is.integer(input$output_dir)) {
      add_log("错误: 请选择输出目录")
      return()
    }
    
    # 检查Qvina2是否可用
    add_log("检查Qvina2是否可用...")
    update_progress(0, 0, 0, 0, "检查Qvina2...", "")
    
    if (!check_qvina2()) {
      add_log("错误: Qvina2未找到或未正确安装")
      add_log("请在左侧输入Qvina2的完整路径，或确保已添加到系统PATH")
      return()
    }
    
    # 检查OpenBabel是否可用
    add_log("检查OpenBabel是否可用...")
    update_progress(0, 0, 0, 0, "检查OpenBabel...", "")
    
    if (!check_openbabel()) {
      add_log("错误: OpenBabel未找到或未正确安装")
      add_log("请在左侧输入OpenBabel的完整路径，或确保已添加到系统PATH")
      return()
    }
    
    # 创建输出目录结构
    dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
    dir.create(file.path(output_dir, "ligands"), showWarnings = FALSE, recursive = TRUE)
    dir.create(file.path(output_dir, "configs"), showWarnings = FALSE, recursive = TRUE)
    dir.create(file.path(output_dir, "results"), showWarnings = FALSE, recursive = TRUE)
    dir.create(file.path(output_dir, "logs"), showWarnings = FALSE, recursive = TRUE)
    
    # 重置结果
    values$results <- data.frame()
    
    # 1. 处理蛋白质
    protein_file <- input$protein_file$datapath
    add_log(paste("蛋白质文件:", basename(protein_file)))
    
    # 计算蛋白质中心
    values$protein_center <- calculate_protein_center(protein_file)
    add_log(paste("蛋白质中心坐标:", 
                  paste(values$protein_center, collapse = ", ")))
    
    # 处理蛋白质
    add_log("处理蛋白质文件...")
    protein_success <- process_protein(protein_file, output_dir)
    if (!protein_success) {
      add_log("蛋白质处理失败，无法继续")
      return()
    }
    
    processed_protein <- file.path(output_dir, "receptor.pdbqt")
    
    # 2. 获取小分子文件
    ligand_dir <- parseDirPath(volumes, input$ligand_dir)
    
    # 根据选择的格式筛选文件
    pattern <- paste0("\\.", input$ligand_format, "$")
    ligand_files <- list.files(ligand_dir, pattern = pattern, 
                               full.names = TRUE, ignore.case = TRUE)
    
    if (length(ligand_files) == 0) {
      add_log(paste("错误: 在", ligand_dir, "中未找到", input$ligand_format, "格式的文件"))
      return()
    }
    
    add_log(paste("找到", length(ligand_files), "个小分子文件"))
    
    # 初始化进度
    update_progress(length(ligand_files), 0, 0, 0, "准备开始处理小分子...", "")
    
    # 处理每个小分子
    results <- list()
    success_count <- 0
    fail_count <- 0
    
    for (i in 1:length(ligand_files)) {
      # 更新当前处理的配体名
      current_ligand <- tools::file_path_sans_ext(basename(ligand_files[i]))
      
      # 处理小分子 - 使用OpenBabel
      add_log(paste("开始处理小分子", i, "/", length(ligand_files), ":", current_ligand))
      ligand_result <- process_ligand_openbabel(ligand_files[i], output_dir, i, length(ligand_files))
      
      if (ligand_result$success) {
        add_log(paste("小分子处理成功:", ligand_result$name))
        
        # 创建配置文件
        config_file <- create_config_file(
          processed_protein, 
          ligand_result$file, 
          output_dir,
          ligand_result$name
        )
        
        # 运行对接
        docking_result <- run_docking(config_file, ligand_result$name, output_dir, ligand_result$file, i, length(ligand_files))
        
        # 更新成功/失败计数
        if (docking_result$success) {
          success_count <- success_count + 1
        } else {
          fail_count <- fail_count + 1
        }
        
        # 保存结果
        result_entry <- data.frame(
          Ligand = ligand_result$name,
          Original_File = basename(ligand_files[i]),
          Energy = ifelse(docking_result$success && !is.na(docking_result$energy), 
                          docking_result$energy, NA),
          Success = docking_result$success,
          Processed_File = ligand_result$file,
          Config_File = config_file,
          Output_File = file.path(output_dir, "results", paste0(ligand_result$name, "_docked.pdbqt")),
          Log_File = file.path(output_dir, "logs", paste0(ligand_result$name, ".txt")),
          Message = ifelse(docking_result$success, 
                           ifelse(!is.na(docking_result$energy), 
                                  paste("成功: 结合能", docking_result$energy, "kcal/mol"),
                                  "成功 (无能量信息)"),
                           paste("失败:", docking_result$message)),
          Timestamp = Sys.time()
        )
        
        results[[i]] <- result_entry
        
        if (docking_result$success) {
          energy_info <- ifelse(!is.na(docking_result$energy), 
                                paste("- 最佳结合能:", docking_result$energy, "kcal/mol"), 
                                "")
          add_log(paste("对接完成:", ligand_result$name, energy_info))
        } else {
          add_log(paste("对接失败:", ligand_result$name, "-", docking_result$message))
        }
      } else {
        fail_count <- fail_count + 1
        add_log(paste("小分子处理失败:", ligand_result$name, "-", ligand_result$message))
        
        # 保存失败记录
        result_entry <- data.frame(
          Ligand = ligand_result$name,
          Original_File = basename(ligand_files[i]),
          Energy = NA,
          Success = FALSE,
          Processed_File = NA,
          Config_File = NA,
          Output_File = NA,
          Log_File = NA,
          Message = paste("处理失败:", ligand_result$message),
          Timestamp = Sys.time()
        )
        
        results[[i]] <- result_entry
      }
      
      # 更新进度
      update_progress(length(ligand_files), i, success_count, fail_count, 
                      "处理小分子中...", current_ligand)
      
      # 强制更新UI
      flush.console()
    }
    
    # 合并所有结果
    if (length(results) > 0) {
      values$results <- do.call(rbind, results)
      
      # 保存结果到CSV
      results_file <- file.path(output_dir, "docking_results.csv")
      write.csv(values$results, results_file, row.names = FALSE)
      
      # 最终进度更新
      update_progress(length(ligand_files), length(ligand_files), success_count, fail_count, 
                      "处理完成！", "")
      
      add_log(paste("所有处理完成！结果已保存到:", results_file))
      add_log(paste("统计: 成功对接:", success_count, "/", nrow(values$results)))
      add_log(paste("      失败:", fail_count, "/", nrow(values$results)))
    }
  }
  
  # 显示蛋白质信息
  output$protein_info <- renderText({
    if (!is.null(input$protein_file)) {
      paste(
        "蛋白质文件:", basename(input$protein_file$name), "\n",
        "蛋白质中心: X =", values$protein_center[1], 
        "Y =", values$protein_center[2],
        "Z =", values$protein_center[3], "\n",
        "盒子尺寸:", input$box_size, "Å ×", input$box_size, "Å ×", input$box_size, "Å\n",
        "搜索详尽度:", input$exhaustiveness, "\n",
        "输出构象数:", input$num_modes
      )
    } else {
      "请先上传蛋白质文件"
    }
  })
  
  # 显示配置文件预览
  output$config_preview <- renderText({
    if (!is.null(input$protein_file) && length(values$protein_center) == 3) {
      paste(
        "receptor = receptor.pdbqt\n",
        "ligand = ligand.pdbqt\n",
        "\n",
        "center_x = ", values$protein_center[1], "\n",
        "center_y = ", values$protein_center[2], "\n",
        "center_z = ", values$protein_center[3], "\n",
        "\n",
        "size_x = ", input$box_size, "\n",
        "size_y = ", input$box_size, "\n",
        "size_z = ", input$box_size,
        sep = ""
      )
    } else {
      "配置将在这里显示..."
    }
  })
  
  # 显示结果表格 - 修复数据整理错误
  output$results_table <- DT::renderDataTable({
    if (nrow(values$results) > 0) {
      # 准备显示数据
      display_df <- values$results %>%
        select(Ligand, Original_File, Energy, Success, Message) %>%
        mutate(Energy = round(as.numeric(Energy), 2))  # 确保能量是数值类型
      
      # 创建数据表
      dt <- DT::datatable(display_df,
                          options = list(
                            pageLength = 10,
                            autoWidth = TRUE,
                            columnDefs = list(
                              list(className = 'dt-center', targets = c(2, 3)),
                              list(width = '200px', targets = 4)
                            )
                          ),
                          rownames = FALSE)
      
      # 只有有数值时才应用颜色格式化
      if (any(!is.na(display_df$Energy))) {
        # 计算分位数用于颜色划分
        valid_energies <- na.omit(display_df$Energy)
        if (length(valid_energies) > 0) {
          # 使用分位数自动确定区间
          quantiles <- quantile(valid_energies, probs = c(0, 0.25, 0.5, 0.75, 1))
          
          # 确保区间是递增的
          if (all(diff(quantiles) >= 0)) {
            dt <- dt %>%
              DT::formatStyle(
                'Energy',
                backgroundColor = DT::styleInterval(
                  quantiles[-c(1, length(quantiles))],  # 去掉第一个和最后一个
                  c('#45B7D1', '#4ECDC4', '#FFE66D', '#FF6B6B')
                )
              )
          } else {
            # 如果分位数不是递增的（很少见），使用固定区间
            add_log("警告: 能量值分位数不是递增的，使用固定区间格式化")
            dt <- dt %>%
              DT::formatStyle(
                'Energy',
                backgroundColor = DT::styleInterval(
                  c(-9, -7, -5),  # 固定区间
                  c('#45B7D1', '#4ECDC4', '#FFE66D', '#FF6B6B')
                )
              )
          }
        }
      }
      
      # 成功/失败列的颜色
      dt <- dt %>%
        DT::formatStyle(
          'Success',
          backgroundColor = DT::styleEqual(
            c(TRUE, FALSE),
            c('#d4edda', '#f8d7da')
          )
        )
      
      return(dt)
    }
  })
  
  # 绘制结合能分布图
  output$energy_plot <- renderPlot({
    if (nrow(values$results) > 0 && sum(!is.na(values$results$Energy)) > 0) {
      valid_results <- values$results %>%
        filter(!is.na(Energy), Success == TRUE)
      
      if (nrow(valid_results) > 0) {
        # 确保能量是数值类型
        valid_results$Energy <- as.numeric(valid_results$Energy)
        
        # 创建直方图
        hist_data <- hist(valid_results$Energy, plot = FALSE)
        
        par(mar = c(5, 4, 2, 2))
        plot(hist_data,
             main = "结合能分布",
             xlab = "结合能 (kcal/mol)",
             ylab = "频数",
             col = "#4ECDC4",
             border = "white",
             las = 1)
        box()
        
        # 添加均值线
        abline(v = mean(valid_results$Energy), col = "#FF6B6B", lwd = 2, lty = 2)
        
        # 添加图例
        legend("topright",
               legend = c(paste("均值:", round(mean(valid_results$Energy), 2), "kcal/mol"),
                          paste("总数:", nrow(valid_results))),
               bty = "n")
      }
    }
  })
  
  # 显示能量统计
  output$energy_stats <- renderTable({
    if (nrow(values$results) > 0 && sum(!is.na(values$results$Energy)) > 0) {
      valid_results <- values$results %>%
        filter(!is.na(Energy), Success == TRUE) %>%
        mutate(Energy = as.numeric(Energy))
      
      if (nrow(valid_results) > 0) {
        data.frame(
          统计量 = c("最小值", "最大值", "平均值", "中位数", "标准差", "总数"),
          值 = c(
            round(min(valid_results$Energy), 2),
            round(max(valid_results$Energy), 2),
            round(mean(valid_results$Energy), 2),
            round(median(valid_results$Energy), 2),
            round(sd(valid_results$Energy), 2),
            nrow(valid_results)
          )
        )
      }
    }
  })
  
  # 监听开始对接按钮
  observeEvent(input$run_docking, {
    # 清除旧的日志和结果
    values$log <- c()
    values$results <- data.frame()
    
    # 重置进度
    update_progress(0, 0, 0, 0, "准备开始...", "")
    
    # 在单独的会话中运行对接
    isolate({
      run_docking_pipeline()
    })
  })
}

# 运行应用
shinyApp(ui = ui, server = server)