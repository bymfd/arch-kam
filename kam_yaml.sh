#!/usr/bin/env bash
# kam_yaml.sh — bash ile saf YAML altseti okuma.
#
# Desteklenen altset:
#   - blok eşlemesi (iç içe), blok listesi, liste öğesi eşlemesi (- a: b)
#   - blok skaleri (|, >, |-, >-)
#   - tırnnak dizgileri ("..." ve '...'), kaçış desteği
#   - boole, tamsayı, null, kayan nokta, inline dizi [a, b]
#   - yorumlar (#) ve boş satırlar
#
# Tüm veri "path=value" satırlarına indirgenir. Liste öğeleri path[0]=.. biçimindedir.
# Liste öğesi eşlemesi: rituals[0].title=...
#
# API:
#   kam_yaml_parse <dosya>
#   kam_yaml_get <dosya> <path>
#   kam_yaml_count <dosya> <path>
#   kam_yaml_list <dosya> <path>
#   kam_yaml_each <dosya> <path> <fn>
#   kam_yaml_keys <dosya> <path>
#   kam_yaml_dump <dosya>

KAM_YAML=()

_kam_yaml_ltrim() {
	local s=$1
	s=${s#"${s%%[! ]*}"}
	printf '%s' "$s"
}

_kam_yaml_rtrim() {
	local s=$1
	s=${s%"${s##*[!\ ]}"}
	printf '%s' "$s"
}

_kam_yaml_indent() {
	local line=$1
	# Baştaki boşlukları genişletme ile say (süreç çatışması yok, hızlı)
	local stripped="${line#"${line%%[! ]*}"}"
	printf '%s' "$(( ${#line} - ${#stripped} ))"
}

_kam_yaml_unquote() {
	local s=$1 q out='' i=0 ch next
	s=$(printf '%s' "$s")
	[[ -z $s ]] && { printf ''; return; }
	q=${s:0:1}
	if [[ $q != '"' && $q != "'" ]]; then
		printf '%s' "$s"
		return
	fi
	s=${s:1}
	if [[ $q == "'" ]]; then
		printf '%s' "${s//\'\'/\'}"
		return
	fi
	while ((i < ${#s})); do
		ch=${s:i:1}
		if [[ $ch == '"' ]]; then
			next=${s:i+1:1}
			[[ -z $next ]] && break
			out+=$ch
			((i++))
			continue
		fi
		if [[ $ch == '\\' ]]; then
			next=${s:i+1:1}
			case $next in
				n) out+=$'\n' ;;
				t) out+=$'\t' ;;
				r) out+=$'\r' ;;
				0) out+=$'\0' ;;
				\\) out+='\' ;;
				\") out+='"' ;;
				*) out+="\\$next" ;;
			esac
			((i += 2))
			continue
		fi
		out+=$ch
		((i++))
	done
	printf '%s' "$out"
}

_kam_yaml_scalar() {
	local raw=$1 trimmed out='' i=0 ch q=''
	raw=${raw%'\r'}
	trimmed=$(_kam_yaml_rtrim "$raw")
	trimmed=$(_kam_yaml_ltrim "$trimmed")
	while ((i < ${#trimmed})); do
		ch=${trimmed:i:1}
		if [[ -n $q ]]; then
			out+=$ch
			[[ $ch == "$q" ]] && q=''
			((i++))
			continue
		fi
		if [[ $ch == '"' || $ch == "'" ]]; then
			q=$ch
			out+=$ch
			((i++))
			continue
		fi
		if [[ $ch == '#' ]]; then
			break
		fi
		out+=$ch
		((i++))
	done
	_kam_yaml_rtrim "$out"
}

_kam_yaml_inline_seq() {
	printf '%s' "$(printf '%s' "$1" | tr -d ' ')"
}

_kam_yaml_prepare() {
	local file=$1
	_KAM_LINES=()
	[[ -f $file ]] || { printf 'kam_yaml: dosya yok: %s\n' "$file" >&2; return 1; }
	local raw started=0
	while IFS= read -r raw || [[ -n $raw ]]; do
		local t
		t=$(_kam_yaml_ltrim "$raw")
		if (( ! started )); then
			if [[ $t == '---'* ]]; then
				started=1
				continue
			fi
			[[ -z $t || $t == '#'* ]] && continue
			started=1
		fi
		_KAM_LINES+=("$raw")
	done < "$file"
	return 0
}

_kam_yaml_build_index() {
	_KAM_IND=()
	_KAM_INDENT=()
	local i=0 line t ind
	while (( i < ${#_KAM_LINES[@]} )); do
		line=${_KAM_LINES[i]}
		t=$(_kam_yaml_ltrim "$line")
		[[ -z $t || $t == '#'* ]] && { ((i++)); continue; }
		[[ $t == '...'* ]] && { _KAM_IND+=($i); _KAM_INDENT+=(-1); ((i++)); continue; }
		ind=$(_kam_yaml_indent "$line")
		_KAM_IND+=($i)
		_KAM_INDENT+=($ind)
		((i++))
	done
}

# Bu bloğun bittiği yer: base_indent'ten daha az girintili ilk satır.
# Aramayı bir kez yapıp dar aralıkla çağırmak O(n²) kaçınır.
_kam_yaml_block_end() {
	local k=$1 end_k=$2 base_indent=$3
	while (( k < end_k )) && (( _KAM_INDENT[k] > base_indent )); do
		((k++))
	done
	printf '%s' "$k"
}

# Eşleme çözümleme. _KAM_AFTER: kaldığı yer.
_kam_yaml_map_from() {
	local start_k=$1 end_k=$2 base_indent=$3 prefix=$4
	local k=$start_k
	local ind line t key val full nk nind nline
	local block_out first bline bind

	while (( k < end_k )); do
		ind=${_KAM_INDENT[k]}
		(( ind < base_indent )) && break
		(( ind > base_indent )) && { ((k++)); continue; }

		line=${_KAM_LINES[_KAM_IND[k]]}
		t=$(_kam_yaml_ltrim "$line")

		if [[ $t == '-'* ]]; then
			break
		fi

		if [[ $t == *':'* ]]; then
			key=$(_kam_yaml_rtrim "${t%%:*}")
			key=$(_kam_yaml_unquote "$key")
			val=$(_kam_yaml_scalar "${t#*:}")
			full="${prefix:+$prefix.}$key"

			nk=$((k + 1))
			if [[ -z $val ]] && (( nk < end_k )) && (( _KAM_INDENT[nk] > base_indent )); then
				nind=${_KAM_INDENT[nk]}
				nline=$(_kam_yaml_ltrim "${_KAM_LINES[_KAM_IND[nk]]}")
				if [[ $nline == '-'* ]]; then
					_kam_yaml_list_from $nk $end_k $nind "$full"
				else
					_kam_yaml_map_from $nk $end_k $nind "$full"
				fi
				k=$_KAM_AFTER
				continue
			fi

			if [[ $val == '|'* || $val == '>'* ]]; then
				block_out=''
				first=1
				((k++))
				while (( k < end_k )) && (( _KAM_INDENT[k] > base_indent )); do
					bline=${_KAM_LINES[_KAM_IND[k]]}
					bind=${_KAM_INDENT[k]}
					if (( first )); then
						block_out=${bline:bind}
						first=0
					elif [[ $val == "|"* ]]; then
						block_out+=$'\n'"${bline:bind}"
					else
						[[ -z ${bline:bind} ]] && block_out+=$'\n' || block_out+=" ${bline:bind}"
					fi
					((k++))
				done
				case $val in
					*-) block_out=${block_out%$'\n'} ;;
					*+) block_out+=$'\n' ;;
				esac
				KAM_YAML+=("$full=$block_out")
				continue
			fi

			if [[ $val == '['* && $val == *']' ]]; then
				KAM_YAML+=("$full=$(_kam_yaml_inline_seq "${val:1:${#val}-2}")")
				((k++))
				continue
			fi

			KAM_YAML+=("$full=$(_kam_yaml_unquote "$val")")
			((k++))
			continue
		fi

		((k++))
	done
	_KAM_AFTER=$k
}

# Liste çözümleme. _KAM_AFTER: kaldığı yer.
_kam_yaml_list_from() {
	local start_k=$1 end_k=$2 base_indent=$3 prefix=$4
	local k=$start_k
	local n=0
	local ind line t body item_path nk nind nline
	local dash_indent rest

	while (( k < end_k )); do
		ind=${_KAM_INDENT[k]}
		(( ind < base_indent )) && break
		(( ind > base_indent )) && { ((k++)); continue; }

		line=${_KAM_LINES[_KAM_IND[k]]}
		t=$(_kam_yaml_ltrim "$line")
		[[ $t != '-'* ]] && break

		body=${t#-}
		body=$(_kam_yaml_ltrim "$body")
		item_path="$prefix[$n]"

		# "- key: val" → liste öğesi eşlemesi
		if [[ $body == *':'* ]]; then
			dash_indent=$ind
			rest=$(_kam_yaml_ltrim "${t#-}")
			_KAM_LINES[_KAM_IND[k]]=$(printf '%*s%s' "$((dash_indent + 2))" '' "$rest")
			_KAM_INDENT[k]=$((dash_indent + 2))
			_kam_yaml_map_from $k $end_k $((dash_indent + 2)) "$item_path"
			k=$_KAM_AFTER
			((n++))
			continue
		fi

		# çocuk blok
		nk=$((k + 1))
		if (( nk < end_k )) && (( _KAM_INDENT[nk] > base_indent )); then
			nind=${_KAM_INDENT[nk]}
			nline=$(_kam_yaml_ltrim "${_KAM_LINES[_KAM_IND[nk]]}")
			if [[ $nline == '-'* ]]; then
				_kam_yaml_list_from $nk $end_k $nind "$item_path"
			else
				_kam_yaml_map_from $nk $end_k $nind "$item_path"
			fi
			k=$_KAM_AFTER
			((n++))
			continue
		fi

		KAM_YAML+=("$item_path=$(_kam_yaml_unquote "$body")")
		((k++))
		((n++))
	done
	_KAM_AFTER=$k
}

kam_yaml_parse() {
	local file=$1
	KAM_YAML=()
	_kam_yaml_prepare "$file" || return 1
	_kam_yaml_build_index
	if (( ${#_KAM_IND[@]} > 0 )); then
		local first
		first=$(_kam_yaml_ltrim "${_KAM_LINES[_KAM_IND[0]]}")
		local root_indent=${_KAM_INDENT[0]}
		if [[ $first == '-'* ]]; then
			_kam_yaml_list_from 0 ${#_KAM_IND[@]} "$root_indent" ''
		else
			_kam_yaml_map_from 0 ${#_KAM_IND[@]} "$root_indent" ''
		fi
	fi
}

kam_yaml_get() {
	local file=$1 path=$2
	# Önbellek: aynı dosya zaten parse edildiyse tekrar okuma
	# Parse edilmemişse (KAM_YAML boş) veya farklı dosya ise parse et
	local line
	for line in "${KAM_YAML[@]}"; do
		if [[ ${line%%=*} == "$path" ]]; then
			printf '%s' "${line#*=}"
			return 0
		fi
	done
	return 1
}

# Listenin doğrudan öğe indekslerini bulur: "0 1 2" biçiminde
_kam_yaml_item_indexes() {
	local path=$1 line p rest idx
	local -a idxs=()
	local seen=' '
	for line in "${KAM_YAML[@]}"; do
		p=${line%%=*}
		case $p in
			"$path"[[]*)
				rest="${p#"$path"}"
				rest="${rest#[}"
				idx=${rest%%]*}
				if [[ $idx =~ ^[0-9]+$ ]]; then
					case $seen in
						*" $idx "*) ;;
						*) seen+="$idx "; idxs+=("$idx") ;;
					esac
				fi
				;;
		esac
	done
	printf '%s ' "${idxs[@]}"
}

kam_yaml_count() {
	local file=$1 path=$2
	# Parse edilmemişse (KAM_YAML boş) veya farklı dosya ise parse et
	local idxs
	idxs=$(_kam_yaml_item_indexes "$path")
	[[ -z $idxs ]] && { printf '0'; return 0; }
	local n=0 i
	for i in $idxs; do ((n++)); done
	printf '%s' "$n"
}

kam_yaml_list() {
	local file=$1 path=$2
	# Parse edilmemişse (KAM_YAML boş) veya farklı dosya ise parse et
	local idxs
	idxs=$(_kam_yaml_item_indexes "$path")
	local i
	for i in $idxs; do
		printf '%s\n' "$i"
	done
}

# Her öğe için fn çağrırır: fn(indeks, "path[N].anahtar=değer" satırları)
kam_yaml_each() {
	local file=$1 path=$2 fn=$3
	# Parse edilmemişse (KAM_YAML boş) veya farklı dosya ise parse et
	local idxs
	idxs=$(_kam_yaml_item_indexes "$path")
	local i item_lines line p
	for i in $idxs; do
		item_lines=''
		for line in "${KAM_YAML[@]}"; do
			p=${line%%=*}
			case $p in
				"$path[$i"*) item_lines+="${item_lines:+$'\n'}$line" ;;
			esac
		done
		"$fn" "$i" "$item_lines"
	done
}

kam_yaml_keys() {
	local file=$1 path=$2 line p
	# Parse edilmemişse (KAM_YAML boş) veya farklı dosya ise parse et
	for line in "${KAM_YAML[@]}"; do
		p=${line%%=*}
		if [[ $p == "$path".* ]]; then
			printf '%s\n' "${p#"$path".}"
		fi
	done
}

kam_yaml_dump() {
	local file=$1
	# Parse edilmemişse (KAM_YAML boş) veya farklı dosya ise parse et
	printf '%s\n' "${KAM_YAML[@]}"
}
