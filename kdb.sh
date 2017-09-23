#!/bin/bash

########################
#
# Variable Declaration
#
########################
declare __KDB_version="1.3"
declare __KDB_name="KDB"
declare __KDB_prompt="(kdb)"

declare __KDB_self_file
declare __KDB_script_file
declare __KDB_continue

## display  &&  undisplay
declare -a __KDB_display
declare -i __KDB_display_idx=0

declare -a __KDB_input




################
#
# IO Functions
#
################
function __kdb_io.o() {
	echo -e "$@"
}

function __kdb_io.pause() {
	declare -a __KDB_tmp
	
	read -e -p "$__KDB_prompt " -a __KDB_tmp
	
	if [[ "${__KDB_tmp[0]}"x != ""x ]];then
		__KDB_input=(${__KDB_tmp[@]})
	fi
}

function __kdb_io.blue(){
	echo -e "\033[1;34m$@\033[0m"
}

function __kdb_io.green(){
	echo -e "\033[1;32m$@\033[0m"
}

function __kdb_io.red(){
	echo -e "\033[1;31m$@\033[0m"
}

function __kdb_io.bluen(){
	echo -ne "\033[1;34m$@\033[0m"
}

function __kdb_io.greenn(){
	echo -ne "\033[1;32m$@\033[0m"
}

function __kdb_io.redn(){
	echo -ne "\033[1;31m$@\033[0m"
}


####################
#
# Array Functions
#
####################
function __kdb_shiftArray() {
	local __KDB_pos="$1"; shift
	local __KDB_arr=($@)
	
	__KDB_arr[__KDB_pos]=""
	
	echo "${__KDB_arr[@]}"
}



#####################
#
# Common Functions
#
#####################
function __kdev_showHelp() {
	cat <<-endh
		调试命令帮助手册:
		  
		  l   - 查看文件最近10行(如果可能)
		  p   - 打印变量值
		  n   - 继续下一步
		  q   - 退出
		  
		  help      - 查看帮助文本
		  display   - 添加监视变量
		  undisplay - 移除监视变量
		
	endh
}

function __kdb_scriptIsSelf() {
	local __KDB_file="$1"
	
	if [[ "$__KDB_file" == "$__KDB_self_file" ]];then
		return 0
	fi
	
	return 1
}

function __kdb_error() {
	echo "Error: $@" 1>&2
}

function __kdb_print_var() {
	local __KDB_var="$1"
	local __KDB_value="\$\{${__KDB_var}\[\@\]\}"
	local __KDB_value="$(eval echo ${__KDB_value})"
	local __KDB_value="$(eval echo ${__KDB_value})"
		
	echo -n "$__KDB_var = "
	__kdb_io.green "${__KDB_value[@]}"
}

function __kdb_display() {
	local __KDB_tmp=""
	local __KDB_idx=0
	
	for ((__KDB_idx = 0; __KDB_idx < __KDB_display_idx; __KDB_idx++ ));do
		__KDB_tmp="${__KDB_display[__KDB_idx]}"
		
		printf "#%d:" "$__KDB_idx"
		__kdb_print_var "$__KDB_tmp"
	done
}

function __kdb_display_find() {
	local _
	local idx=0
	
	for _ in "${__KDB_display[@]}"; do
		if [[ "$_" == "$1" ]];then
			(( idx++ ))
			return $idx
		fi
		
		(( idx++ ))
	done
	
	return 0
}

function __kdb_add_display_var() {
	__kdb_display_find "$1";
	local __KDB_r="$?"
	(( __KDB_r-- ))
	
	if [[ "$__KDB_r" != -1 ]];then
		return
	fi
	
	__KDB_display[__KDB_display_idx]="$1"
	(( __KDB_display_idx++ ))
	
	echo "已添加监视: $1"
}

function __kdb_remove_display_var() {
	__kdb_display_find "$1";
	local __KDB_idx=$?
	(( __KDB_idx-- ))
	
	if [[ "__KDB_idx" == -1 ]];then
		return
	fi
	
	(( __KDB_display_idx-- ))
	
	__KDB_display=($(__kdb_shiftArray "$__KDB_idx" ${__KDB_display[@]}))
	
	echo "已移除监视: $1"
}

####################
#
# Core Functions
#
####################
function __kdb_action_l() {
	local __KDB_no="$1"
	
	local __KDB_l1="$((__KDB_no - 4))"
	local __KDB_l2="$((__KDB_no + 5))"
	
	if (( __KDB_l1 < 1 ));then
		__KDB_l1=1
	fi
	
	local __KDB_cl="$__KDB_l1"
	
	sed -n "${__KDB_l1},${__KDB_l2}p" $__KDB_script_file | \
		while IFS=$'\n' read __KDB_l;do
			__KDB_l=$(echo -e "$__KDB_l" | sed 's/\t/  /g')
			__KDB_l=$(echo -e "$__KDB_l" | sed 's/    /  /g')
			if (( __KDB_cl == __KDB_no ));then
				printf "   => %2d: %s\n" "$__KDB_cl" "$__KDB_l"
			else
				printf "      %2d: %s\n" "$__KDB_cl" "$__KDB_l"
			fi
			(( __KDB_cl++ ))
		done
}

function __kdb_action_p() {
	local __KDB_arg
	
	for __KDB_arg in $@;do
		echo -n "    "
		__kdb_print_var "$__KDB_arg"
	done
}

function __kdb_action_q() {
	exit 1
}

function __kdb_action_n() {
	__KDB_continue=true
}

function __kdb_action_help() {
	__kdev_showHelp
}

function __kdb_action_display() {
	if [[ "$1"x == ""x ]];then
		return 1
	fi
	
	local _
	for _ in $@;do
		__kdb_add_display_var "$_"
	done
}

function __kdb_action_undisplay() {
	if [[ "$1"x == ""x ]];then
		return 1
	fi
	
	local _
	
	for _ in $@;do
		__kdb_remove_display_var "$_"
	done
}


function __kdb_do_debug() {
	local __KDB_file="$1"
	local __KDB_line="$2"
	local __KDB_func="${3:-<null>}"
	local __KDB_command="$4"
	
	__KDB_continue=false
	
	if __kdb_scriptIsSelf "$__KDB_file";then
		return 0;
	fi
	
	__kdb_io.red "断点在 ${__KDB_func} 函数于 ${__KDB_file}:${__KDB_line}"
	__kdb_io.green "    ${__KDB_line}: $__KDB_command"
	
	__kdb_display
	
	while :;do
		set -o history
		__kdb_io.pause
		set +o history
	
		local __KDB_action=${__KDB_input[0]}
		local __KDB_arr=($(__kdb_shiftArray 0 ${__KDB_input[@]}))
		
		if [[ "$__KDB_action"x == ""x ]];then
			continue
		fi
		
		case $__KDB_action in
			"l" ) 
				__kdb_action_l "$__KDB_line" ;;
			
			"p" ) 
				__kdb_action_p "${__KDB_arr[@]}" ;;
			
			"n" ) 
				__kdb_action_n ;;
			
			"q" ) 
				__kdb_action_q ;;
				
			"help" )
				__kdb_action_help ;;
				
			"display" )
				__kdb_action_display "${__KDB_arr[@]}";;
				
			"undisplay" )
				__kdb_action_undisplay "${__KDB_arr[@]}";;
			
			* )
				__kdb_error "未知命令: $__KDB_action, 输入 help 查看帮助" ;;
		esac
		
		if [[ "$__KDB_continue" == true ]];then
			break;
		fi
	done
	
	return 0;
}



######################
#
# Entrance
#
######################
__KDB_did=false
__KDB_self_file="$0";
__KDB_script_file="$1"; shift

if [[ "$__KDB_script_file"x == ""x ]];then
	echo "  Usage: kdb <script> [ARGS]"
	echo "    run script in debug mode"
	exit 1
fi

set -o vi
set -o functrace


trap '__kdb_do_debug "${BASH_SOURCE[0]}" "$LINENO" "$FUNCNAME" "$BASH_COMMAND" "$@"' DEBUG

. $__KDB_script_file

