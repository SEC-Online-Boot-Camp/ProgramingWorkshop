# レジストリのPATHを読み直す。scoopや各種インストーラでPATHが更新されていても、
# このプロセスの$env:Pathにはまだ反映されていないことがあるため。
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
