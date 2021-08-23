#! /usr/bin/env sh
# SPDX-License-Identifier: 0BSD
#
# Copyright © 2021 Alex Minghella <a@minghella.net>
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
# -----------------------------------------------------------------------------

: "${PROCDOC_PATH:="./procdoc.awk"}"

procdoc_version="0.1.0"
procdoc_help="
usage: ${0##*/} [-fghv] [-F <format>] [-o <file>] [-t <type>] [--] [<file>]...

Options:
 -F <format>    Write final output in <format>. Available formats may be listed
                with -F list.
 -f             Output only function blocks.
 -g             Output only generic blocks.
 -h             Display this help message.
 -o <file>      Write formatted output to <file>.
 -t <type>      Use <type> as the default filetype.
 -v             Display version information.
"

# NOTE: This needs to play nicely with the shell's word splitting.
procdoc_output_formats="\
asciidoc
none
"

tmpdir="$(mktemp -d -p "${TMPDIR:-"/tmp"}")"
trap 'rm -rf "${tmpdir}"' EXIT

##
# fatal - Write a formatted error message to man:stderr(3) and exit.
#
# @fmt: A man:printf(3)-like format string.
# @...: Parameters corresponding to the provided format string.
#
# @return: None. (Does not return.)
fatal()
{
	_fatal_fmt="${1}"
	shift

	# shellcheck disable=SC2059
	printf "fatal: ${_fatal_fmt}\\n" "${@}" >&2
	exit 1
}

##
# shquote - Quote a string for evaluation by the shell.
#
# @1: String to quote.
#
# @return: Provided string, quoted appropriately, written to man:stdout(3).
shquote()
{
	printf "%s\\n" "${1}" | sed "s/'/'\\\\''/g; 1s/^/'/; \$s/\$/'/"
}

##
# realpath - Determine the real absolute path of a file.
#
# @1: File to determine the path of.
#
# @return: Absolute path written to man:stdout(3). May call fatal() on
#          man:cd(1) failure.
#
# NOTE: All except the final path component must already exist.
realpath()
{
	if [ "${1%/*}" != "${1}" ]; then
		(
			cd "${1%/*}/" || exit 1
			_pwd="$(pwd -P)"
			printf "%s%s\\n" "${_pwd%/}/" "${1##*/}"
		) || fatal "failed to cd(1): %s" "${1%/%}/"
	else
		_pwd="$(pwd -P)"
		printf "%s%s\\n" "${_pwd%/}/" "${1}"
	fi
}

##
# checkfmt - Determine whether we can produce a given format.
#
# @1: Format to check.
#
# @return: 0 if the provided format is known, else 1.
checkfmt()
{
	for _checkfmt_f in ${procdoc_output_formats}; do
		if [ "${1}" = "${_checkfmt_f}" ]; then
			return 0
		fi
	done

	return 1
}

##
# invoke - Process files with procdoc.awk.
#
# @1: Shell-quoted options to pass to procdoc.awk.
# @2: Shell-quoted paths to pass to procdoc.awk.
#
# @return: 0 if all files were processed successfully, 1 otherwise.
invoke()
{
	if [ ! -f "${PROCDOC_PATH}" ]; then
		fatal "file does not exist: %s" "${PROCDOC_PATH}"
	fi

	eval "set -- ${1} -- ${2}"
	awk -f "${PROCDOC_PATH}" -- "${@}"
}

##
# format_generics - Apply output "formatting" to generic blocks.
#
# @1: Output format name. May contain additional format-specific data appended
#     after a colon.
# @2: Path to file containing procdoc output.
#
# @return: "Formatted" generic blocks written to man:stdout(3).
#
# The only actual formatting we perform here is wrapping lines at roughly 80
# characters for easier reading with the "none" format. With all other formats,
# we don't actually touch the text - we just assume it's syntactically correct
# for the output markup language. (We also assume that "none" blocks, being
# plain text, are valid in all output formats we know about.)
format_generics()
{
	case "${1%%:*}" in
	none)
		jq -r '
			select(.type == "generic" and .markup == "none") |
			.content[], ""
			' "${2}" | fold -s -w 80
		;;
	*)
		jq -r "
			select(.type == \"generic\") |
			select(.markup == \"none\" or .markup == \"${1%%:*}\") |
			.content[], \"\"
			" "${2}"
		;;
	esac
}

##
# _format_functions - Do as much processing as possible in one jq(1) pass.
#
# @1: Path to file containing output from procdoc.awk.
#
# @return: None.
#
# Extracting and manipulating all the relevant information from a function
# block is much faster if we do it all at once. This function does exactly that
# and writes three types of lines. Each line has three tab-separated values:
# a type and two line-specific data values.
#
# "name" lines:: The first data value is the block ID, the identifier name, and
# its members enclosed in parentheses. The second is the short description
# string.
#
# "member" lines:: The first data value is the identifier of a member, the
# second is its associated description.
#
# "description" lines:: The first data value is the heading, the second is the
# paragraph content. The heading may be `":"`, indicating that there is no
# heading for this paragraph. This is due to how read(1) functions.
#
# NOTE: For each block, the "name" line is emitted first, followed by any
#       "member" lines, and then any "description" lines. Special members, such
#       as `@return`, are emitted after normal members.
_format_functions()
{
	jq -r '
		select(.type == "function") |
		(
			["", .id, .content.name] | join("_")
		) as $id |
		(
			$id +
			"(" +
			(
				[
					.content.members[].name |
					select(test("^[^@]"; ""))
				] | join(", ")
			) +
			")"
		) as $f |
		.content | (
			(
				["name", $f, .["short-description"]] |
				join("\t")
			),
			(
				.members[] |
				.description |= gsub(
					"<<(?<n>(?!_)[[:alnum:]_-]+)>>";
					("<<" + $id + "-" + (.n) + ">>")
				) |
				(
					(select(.name | test("^[^@]"; "")) |
					["member", .name, .description] |
					join("\t")),
					(select(.name | test("^@"; "")) |
					["member", .name, .description] |
					join("\t"))
				)
			),
			(
				.description[] |
				.heading |= (sub("^$"; ":")) |
				["description", .heading, .paragraph] |
				join("\t")
			)
		)' "${1}"
}

##
# format_functions_asciidoc - Output Asciidoc-formatted function documentation.
#
# @1: Output format name. May contain additional format-specific data appended
#     after a colon.
# @2: Path to file containing output from procdoc.awk.
#
# @return: Function documentation written to man:stdout(3).
#
# If there is additional format data, then it is used to determine the
# heading/subheading levels for the output. Currently available are 2 (the
# default), 3, and 4. All other data are silently ignored.
#
# We don't bother wrapping text here since it's not really intended to be read
# directly, but passed through man:asciidoctor(1) or similar.
format_functions_asciidoc()
{
	_heading="=="
	_subheading="==="

	if [ -n "${1#*:}" ]; then
		case "${1#*:}" in
		3)
			_heading="==="
			_subheading="===="
			;;
		4)
			_heading="===="
			_subheading="====="
			;;
		*)
			# Ignore. Asciidoc doesn't have any more levels of
			# headings and level one is semantically wrong here.
			;;
		esac
	fi

	# NOTE: Though it's not strictly required by POSIX, there's likely an
	#       implicit subshell here due to the pipe.
	_format_functions "${2}" |
	while IFS="	" read -r _type _data1 _data2; do
		case "${_type}" in
		name)
			# "name" _<id>_<function-name> <short-description>
			printf "%s %s\\n\\n" "${_heading}" "${_data1#_*_}"

			if [ -n "${_data2}" ]; then
				printf "%s\\n\\n" "${_data2}"
			fi

			_did_memb=0
			_id="${_data1%%(*}"
			;;
		member)
			# "member" <member-name> <member-description>
			case "${_data1}" in
			@return)
				if [ "${_did_memb}" -eq 1 ]; then
					printf "\\n.Return Value\\n%s\\n\\n" \
						"${_data2}"
				else
					printf ".Return Value\\n%s\\n\\n" \
						"${_data2}"
				fi
				;;
			*)
				if [ "${_did_memb}" -eq 0 ]; then
					printf "[.member-list, title=Parameters]\\n"
				fi

				if [ "${_data1}" = "..." ]; then
					_argid="${_id}-varargs"
				else
					_argid="${_id}-${_data1}"
				fi

				printf "[[%s,%s]]*%s*:: %s\\n" \
					"${_argid}" "**${_data1}**" \
					"${_data1}" "${_data2}"
				;;
			esac

			_did_memb=1
			;;
		description)
			# "description" <heading> <paragraph>

			# We need an extra line break to avoid confusing the
			# Asciidoc processor.
			if [ "${_did_memb}" -eq 1 ]; then
				printf "\\n"
			fi

			case "${_data1}" in
			CAUTION|IMPORTANT|NOTE|TIP|WARNING)
				# Admonition blocks.
				printf "%s: %s\\n\\n" "${_data1}" "${_data2}"
				;;
			:)
				printf "%s\\n\\n" "${_data2}"
				;;
			*)
				printf "%s %s\\n\\n%s\\n\\n" "${_subheading}" \
					"${_data1}" "${_data2}"
				;;
			esac
			;;
		esac
	done
}

##
# format_functions_none - Output function documentation in a plain text format.
#
# @1: Output format name. May contain additional format-specific data appended
#     after a colon.
# @2: Path to file containing output from procdoc.awk.
#
# @return: Function documentation written to man:stdout(3).
#
# We try to indent things and wrap at roughly 80 columns for easier reading.
# This is not meant to be a "pretty" output format, but something more readable
# than a compact JSON dump. (You can get the raw JSON with much less overhead
# by just using the procdoc.awk script by itself anyway.)
format_functions_none()
{
	# NOTE: Though it's not strictly required by POSIX, there's likely an
	#       implicit subshell here due to the pipe.
	_format_functions "${2}" |
	while IFS="	" read -r _type _data1 _data2; do
		case "${_type}" in
		name)
			# "name" <function-name> <short-description>
			printf "%s\\n\\n" "${_data1#_*_}"

			if [ -n "${_data2}" ]; then
				printf "%s\\n" "${_data2}" \
					| fold -s -w 76 \
					| sed 's/^/    /'
				printf "\\n"
			fi

			_did_memb=0
			;;
		member)
			# "member" <member-name> <member-description>
			case "${_data1}" in
			@return)
				printf "    Return Value:\\n"
				printf "%s\\n" "${_data2}" \
					| fold -s -w 76 \
					| sed 's/^/    /'
				printf "\\n"
				;;
			*)
				if [ "${_did_memb}" -eq 0 ]; then
					printf "    Parameters:\\n"
				fi

				printf "* %s: %s\\n" "${_data1}" "${_data2}" \
					| fold -s -w 76 \
					| sed '
						/^\*/ {
							s/^/    /
							p
							d
						}

						s/^/      /
						'
				printf "\\n"
				;;
			esac

			_did_memb=1
			;;
		description)
			# "description" <heading> <paragraph>
			if [ "${_data1}" = ":" ]; then
				printf "%s\\n\\n" "${_data2}" \
					| fold -s -w 76 \
					| sed 's/^/    /'
			else
				printf "    %s\\n" "${_data1}"
				printf "%s\\n\\n" "${_data2}" \
					| fold -s -w 72 \
					| sed 's/^/        /'
			fi
			;;
		esac
	done
}

default_type=""
format=""
function_blocks=0
generic_blocks=0
input=""
output=""

while getopts ":F:fghi:o:t:v" opt; do
	case "${opt}" in
	F)
		format="${OPTARG}"
		;;
	f)
		function_blocks=1
		generic_blocks=0
		;;
	g)
		function_blocks=0
		generic_blocks=1
		;;
	h)
		printf "%s\\n" "${procdoc_help}"
		exit 0
		;;
	i)
		input="${OPTARG}"
		;;
	o)
		output="${OPTARG}"
		;;
	t)
		default_type="${OPTARG}"
		;;
	v)
		printf "procdoc version %s\\n" "${procdoc_version}"
		exit 0
		;;
	:)
		fatal "option requires argument: -%s" "${OPTARG}"
		;;
	*)
		fatal "invalid option: -%s" "${OPTARG}"
		;;
	esac
done
shift "$((OPTIND - 1))"

if [ -z "${format}" ]; then
	format="asciidoc"
elif [ "${format}" = "list" ]; then
	# shellcheck disable=SC2086
	printf "%s\\n" ${procdoc_output_formats}
	exit 0
elif ! checkfmt "${format%%:*}"; then
	fatal "unknown output format: %s" "${format%%:*}"
fi

if [ "${function_blocks}" -eq 1 ]; then
	procdoc_flags="${procdoc_flags# } -f"
elif [ "${generic_blocks}" -eq 1 ]; then
	procdoc_flags="${procdoc_flags# } -g"
fi

if [ -n "${default_type}" ]; then
	procdoc_flags="${procdoc_flags# } -t $(shquote "${default_type}")"
fi

if [ -z "${input}" ]; then
	paths=""
	while [ -n "${1}" ]; do
		if [ ! -f "${1}" ]; then
			fatal "file does not exist: %s" "${1}"
		fi

		paths="${paths# } $(shquote "$(realpath "${1}")")"
		shift
	done

	# The Awk script may fail for various reasons and will attempt
	# to print a useful error message to stderr(3). Make sure it
	# didn't fail before proceeding.
	input="$(mktemp -p "${tmpdir}")"
	if ! invoke "${procdoc_flags}" "${paths}" >"${input}"; then
		exit 1
	fi
elif [ "${input}" = "-" ]; then
	# If we were told to use a file as input rather than getting the Awk
	# script to generate it, first check that it is valid JSON. Note that
	# this does _not_ check that it's valid input _for us_, only that it's
	# valid JSON.
	input="$(mktemp -p "${tmpdir}")"
	if ! jq -c '.' >"${input}"; then
		fatal "invalid JSON input"
	fi
else
	if ! jq -c '.' "${input}" >/dev/null; then
		fatal "invalid JSON input"
	fi
fi

if [ -z "${output}" ] || [ "${output}" = "-" ]; then
	exec 9>&1
elif realpath "${output}" >/dev/null; then
	exec 9>"${output}"
else
	fatal "unable to create output file: %s" "${output}"
fi

format_generics "${format}" "${input}" >&9
"format_functions_${format%%:*}" "${format}" "${input}" >&9
