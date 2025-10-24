set -xe
pip install delvewheel

if [[ ${OS-NAME} -eq "windows-latest" ]]; then
    # Since it has the correct platform tag, we don't need to rename the wheel for windows-latest
    # for f in dist/*.whl; 
    #     do mv $f "${f/%any.whl/$WHEEL_PLAT.whl}";
    # done
    delvewheel repair -w $1 $2
    exit 0
fi

# repair for windows arm64
./tools/repair_wheel_for_win_arm64.bat $1 $2