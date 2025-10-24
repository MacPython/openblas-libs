if "%if_bits%"=="32" (
    move /Y pyproject.toml.bak pyproject.toml
    move /Y "%CD%\ob64_backup" "%ob_64%"
)

delvewheel repair -w %1 %2

:: Rename the wheel
@REM for %%f in (dist\*any.whl) do (
@REM     set WHEEL_FILE=dist\%%f
@REM     set "filename=%%~nxf"
@REM     set "newname=!filename:any.whl=win_arm64.whl!"
@REM     ren "dist\!filename!" "!newname!"
@REM )