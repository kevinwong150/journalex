@echo off
setlocal enabledelayedexpansion

REM Batch script to remove all "Account Information" rows from CSV files
REM Usage: remove_account_info.bat [input_path] [output_suffix]
REM   input_path: CSV file or directory containing CSV files
REM   output_suffix: suffix to add to output files (default: "_no_account_info")
REM If no arguments provided, it will process all CSV files in current directory

set input_path=%1
set output_suffix=%2

REM Set default values if not provided
if "%output_suffix%"=="" set output_suffix=_no_account_info

REM If no input path provided, process current directory
if "%input_path%"=="" goto process_current_dir

REM Check if input path exists
if not exist "%input_path%" (
    echo Error: Input path "%input_path%" not found!
    pause
    exit /b 1
)

REM Check if input is a file or directory
dir "%input_path%" >nul 2>&1
if errorlevel 1 goto process_single_file

REM Input is a directory
echo Processing directory: %input_path%
echo Looking for CSV files...
echo.

for %%f in ("%input_path%\*.csv") do (
    if exist "%%f" call :process_file "%%f"
)

echo.
echo Processing complete!
pause
exit /b 0

:process_current_dir
echo Processing current directory for CSV files...
echo.

for %%f in (*.csv) do (
    if exist "%%f" call :process_file "%%f"
)

echo.
echo Processing complete!
pause
exit /b 0

:process_single_file
REM Input is a file
echo Processing single file: %input_path%
call :process_file "%input_path%"
pause
exit /b 0

REM Function to process a single CSV file
:process_file
set current_file=%~1
set file_name=%~n1
set file_dir=%~dp1
set output_file=%file_dir%%file_name%%output_suffix%.csv

echo.
echo Processing file: %current_file%
echo Output file: %output_file%

REM Remove existing output file if it exists
if exist "%output_file%" del "%output_file%"

set removed_count=0

REM Process the file line by line
for /f "usebackq delims=" %%a in ("%current_file%") do (
    set line=%%a
    set skip_line=0
    
    REM Check if line starts with "Account Information" (with quotes)
    echo !line! | findstr /b /c:"\"Account Information\"" >nul 2>&1
    if not errorlevel 1 set skip_line=1
    
    REM Check if line starts with Account Information (without quotes)  
    echo !line! | findstr /b /c:"Account Information," >nul 2>&1
    if not errorlevel 1 set skip_line=1
    
    if !skip_line! equ 1 (
        REM Line starts with "Account Information", skip it
        set /a removed_count=removed_count+1
        echo   Removing Account Information row
    ) else (
        REM Line does not start with "Account Information", keep it
        echo !line!>>"%output_file%"
    )
)

REM Count lines in both files
for /f %%i in ('type "%current_file%" ^| find /c /v ""') do set original_lines=%%i
for /f %%i in ('type "%output_file%" ^| find /c /v ""') do set new_lines=%%i

echo   Original lines: !original_lines!
echo   New lines: !new_lines!
echo   Rows removed: !removed_count!
echo   Output: %output_file%

goto :eof
