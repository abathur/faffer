#! /usr/bin/env bash

# This script explores a fuzzing/tree-shaking approach to
# figuring out if there are dangling unresolved deps in a
# bash/shell script.
#
# This is a little nuts; it may be hard to follow without the high-alt view:
#
# 1. It tries to find unresolved deps by emptying PATH and setting the default hook
#    command_not_found_handle to report anything it gets called for. It is not actually
#    trying to run these* executables--that's why the path is empty.
#
# 2. It tries to juice the number of code paths by engaging in some weird alias-
#    based meta-programming dark magic.
#
# 3. It's currently meant to be run multiple times in all 3 modes. I don't have a good
#    sense of how many runs are useful, so those decisions are up the caller for now.
#
# 4. It sources the target script. If the target script does magic to resist sourcing,
#    it won't work for now. I may also make an injectable version...
#
# It's ideal to run this in some sort of chroot/sandbox so that there's a lower chance
# something it runs will redirect output over a real file, and to limit its ability to
# run hard-coded paths. I am, in fact, writing it with the intent of running it inside
# the sandbox in nix-build.
#
# Other caveats:
# 1. The script will almost certainly throw errors. That's fine. The point isn't to
#    run clean, it's just to try and explore/enumerate. I may later hide this output.
#
# 2. It currently outputs a count and list of dependencies by line. If this proves
#    viable at some point I'll try to split the focus to both collect this line-oriented
#    information for fixing the script, but also collect a list of unique externals.
#
# 3. There'll also be some process of figuring out exactly how this fits in with other
#    tools.
#
# Usage:
# ./faffer.bash <minimal|all|random> <target script>

shopt -s expand_aliases # aliases on for dark magic

# I'd prefer to `set -o noclobber` here to make this less-likely to
# overwrite files in some chaotic manner, but faffer itself needs to
# be able to write to FDs, noclobber is indiscriminate :(
#
# I'd also like to be able to use a restricted shell to make this a little more usable
# without a chroot/sandbox, but the same issue applies.

__faff_record_dep(){
	# first arg is type
	echo "${BASH_SOURCE[2]}:${BASH_LINENO[1]} - runtime dependency on $1${1:+ }'$2' (full command: '${@:2}')"
} 1>&$faffer

command_not_found_handle(){
	__faff_record_dep "" "$@" # blank 1st arg is "type"
	__coinflip # i.e., return random 0/1
}

__faff_report(){
	mapfile -t report
	[[ ${#report[@]} -gt 0 ]] && echo "Found ${#report[@]} runtime dependencies!" && printf "%s\n" "${report[@]}" && exit 10
	echo "All clean!" && exit 0
}
__faff_record_typed_dep(){
	[[ ! -r $1 ]] &&  __faff_record_dep "$@"
}
trim_quotes() { # something borrowed: dylanaraps/pure-bash-bible
    # Usage: trim_quotes "string"
    : "${1//\'}"
    printf '%s\n' "${_//\"}"
}

__handle_complex_case_line(){
	# we want to try to run the line, but more condensed statements
	# may have case furniture that just won't run here. We'll
	# try to cut it down first
	line="$1"
	line="${line##*)}" # rm leading case match?
	line="${line//;;/}" # rm the double semicolon
	$(trim_quotes "$line") # run what's left
}

# get a little wild
__slurp_case(){
	# $2 == the "in" from the end of the line
	echo "case called with $1"
	mapfile -t file_data
	for line in "${file_data[@]}"; do
		# pull out the most-complex case for special handling
		[[ "$line" == *")"*";;" ]] && (__handle_complex_case_line "$line"; continue)
		# skip the normal pattern-match and block-end lines
		[[ "$line" == *")" ]] && continue
		[[ "$line" == *";;" ]] && continue
		# hopefully a clean line; try to run (may need something more robust)
		$(trim_quotes "$line")
	done
	printf '%s\n' "${file_data[@]}"
}

# Randomizers
__random_noise(){
	# the world can be noisy; let's randomly make some
	((chance1=RANDOM % 3))
	[[ $chance1 == 0 ]] && echo "this will have to be noisy enough for now; maybe more randomness later"
	((chance2=RANDOM % 12))
	[[ $chance2 == 0 ]] && echo "this will have to be noisy enough for now; maybe more randomness later" 1>&2
}
__random_repeat(){
	__random_noise
	((mod=RANDOM / 2000))
	((mod++)) # avoid div by 0
	((ret=RANDOM % mod))
	return $ret
}
__coinflip(){
	__random_noise
	((ret=RANDOM % 2))
	return $ret
}

faff(){
	\source $@
}

# use a named FD; leave STDIN and STDERR alone for the program we're infecting
exec {faffer}> >(__faff_report >&2)


# BEGIN BOOTSTRAP DEPS

# rewrite if/elif to make them
__overwrite_if(){ alias if="if __coinflip ||"; } # TODO: try to cut the && back out?
__overwrite_elif(){ alias elif="elif __coinflip ||"; }
__overwrite_case(){ alias case=$'__slurp_case <<- esac'; }
__overwrite_select(){ alias select="for"; }
__overwrite_until(){ alias until="until __random_repeat"; }
__overwrite_while(){ alias while="while ! __random_repeat"; }
__overwrite_source(){
	alias source="__faff_record_typed_dep sourcing" .="__faff_record_typed_dep sourcing"
}

__bootstrap_all(){
	__overwrite_keywords "if" "elif" "case" "select" "until" "while" "source"
}

__bootstrap_minimal(){
	__overwrite_keywords "source"
}

__overwrite_keywords(){
	for keyword in $@; do
		__overwrite_${keyword}
	done
}

__bootstrap_random(){
	__coinflip && set -- $@ if
	__coinflip && set -- $@ select
  __coinflip && set -- $@ until
  __coinflip && set -- $@ while
  __coinflip && set -- $@ elif
  __coinflip && set -- $@ case
  __overwrite_keywords "source" "$@"
}
# END BOOTSTRAP DEPS

"__bootstrap_${1}" # actually bootstrap

# superstitiously expunge bootstrap to minimize surface area
unset __overwrite_if __overwrite_elif __overwrite_case __overwrite_select __overwrite_until __overwrite_while __overwrite_source __bootstrap_all __bootstrap_minimal __overwrite_keywords __bootstrap_minimal


# TODO: tempted to treat aliases (or at least the aliases we set)
# like the cool kids table, but I'll hold for evidence it's a problem?
# alias(){
# 	:
# }
# If the path is completely empty, the command_not_found_handle won't work?
declare -xr PATH=':' command_not_found_handle alias faff

faff $2
