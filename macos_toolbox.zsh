#!/bin/zsh

# --- 0. CHECKS ---
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Starting installation..."
    echo "Note: You might be asked for your Mac password."
    
    # Run the official installer
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
        
        # Make brew available immediately in the current session
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        
        echo "--------------------------------------------------"
        echo "Homebrew installed successfully!"
        echo "--------------------------------------------------"
    else
        echo "Error: Homebrew installation failed."
        exit 1
    fi
else
    echo "Homebrew is already installed."
fi

# --- 1. COLORS & STYLE ---
autoload -U colors && colors
zmodload zsh/terminfo

BOLD="\e[1m"
RESET="\e[0m"
CHECKMARK="[✔]"
CROSSMARK="[✘]"
UNCHECKED="[ ]"

# --- 2. THE STORAGE ---
typeset -A selection_map
typeset -A uninstall_map
search_query=""
results=()
cursor=1
is_searching=false
view_mode="search" 

# --- 3. PAINTING THE SCREEN ---
draw_menu() {
    clear
    echo "${BOLD}MACOS TOOLBOX${RESET}"
    echo "--------------------------------------------------"
    
    case "$view_mode" in
        "selection")
            echo "VIEW: ${fg[green]}Install Queue${reset_color}"
            echo "KEYS: [v] Next Mode  [SPACE] Remove  [ENTER] Start" ;;
        "uninstall")
            echo "VIEW: ${fg[red]}Uninstall Queue${reset_color}"
            echo "KEYS: [v] Next Mode  [SPACE] Unmark  [ENTER] Start" ;;
        "installed")
            echo "VIEW: ${fg[blue]}Local Packages${reset_color}"
            echo "KEYS: [v] Next Mode  [SPACE] Mark for Deletion" ;;
        *)
            echo "QUERY: $fg[yellow]${search_query:-"(Start typing...)"}$reset_color"
            echo "KEYS: [TAB] Search Brew  [v] Views  [SPACE] Select" ;;
    esac
    echo "--------------------------------------------------"

    if [[ "$is_searching" == true ]]; then
        echo -ne "\n  ${fg[cyan]}Checking Brew...${reset_color}\n"
        echo -ne "  [${fg[yellow]}■■■■■■■■■■■■■■■■■${reset_color}] 100%\r"
    else
        local display_list=()
        if [[ "$view_mode" == "selection" ]]; then
            display_list=(${(k)selection_map[(R)true]})
        elif [[ "$view_mode" == "uninstall" ]]; then
            display_list=(${(k)uninstall_map[(R)true]})
        elif [[ "$view_mode" == "installed" ]]; then
            local all_local=(${(f)"$(brew list --formula; brew list --cask)"})
            [[ ${#search_query} -gt 0 ]] && display_list=(${(M)all_local:#${search_query}*}) || display_list=($all_local)
        else
            display_list=($results)
        fi

        local list_size=${#display_list}
        [[ $cursor -gt $list_size ]] && cursor=$list_size
        [[ $cursor -lt 1 && $list_size -gt 0 ]] && cursor=1

        if [[ $list_size -eq 0 ]]; then
            echo -e "\n  $fg[yellow](Nothing here)$reset_color"
        else
            for i in {1..$list_size}; do
                local item="${display_list[$i]}"
                local pref="  "
                [[ $i -eq $cursor ]] && pref="$fg[cyan]> $reset_color"
                
                local item_icon="$UNCHECKED"
                [[ ${selection_map[$item]} == "true" ]] && item_icon="${fg[green]}$CHECKMARK${reset_color}"
                [[ ${uninstall_map[$item]} == "true" ]] && item_icon="${fg[red]}$CROSSMARK${reset_color}"
                
                echo -e "${pref}${item_icon} ${item}"
            done
        fi
    fi

    local sel_c=0; for k in ${(k)selection_map}; do [[ ${selection_map[$k]} == "true" ]] && ((sel_c++)); done
    local del_c=0; for k in ${(k)uninstall_map}; do [[ ${uninstall_map[$k]} == "true" ]] && ((del_c++)); done
    echo -e "\n--------------------------------------------------"
    echo -e "Queue: ${fg[green]}+$sel_c${reset_color} ${fg[red]}-$del_c${reset_color} | [v] to switch views"
}

# --- 4. LISTENING TO YOU ---
while true; do
    draw_menu
    read -k 1 key
    case "$key" in
        $'\x09') # TAB
            if [[ ${#search_query} -ge 2 && "$view_mode" == "search" ]]; then
                is_searching=true; draw_menu
                results=(${(f)"$(brew search "$search_query" | head -n 30)"})
                is_searching=false; cursor=1 
            fi ;;
        "v"|"V") # VIEWS
            if [[ "$view_mode" == "search" ]]; then view_mode="selection"
            elif [[ "$view_mode" == "selection" ]]; then view_mode="installed"
            elif [[ "$view_mode" == "installed" ]]; then view_mode="uninstall"
            else view_mode="search"; fi
            cursor=1 ;;
        " ") # SPACE
            local active_list=()
            if [[ "$view_mode" == "selection" ]]; then active_list=(${(k)selection_map[(R)true]})
            elif [[ "$view_mode" == "uninstall" ]]; then active_list=(${(k)uninstall_map[(R)true]})
            elif [[ "$view_mode" == "installed" ]]; then active_list=(${(f)"$(brew list --formula; brew list --cask)"})
            else active_list=($results); fi
            
            if [[ ${#active_list} -gt 0 ]]; then
                local target="${active_list[$cursor]}"
                if [[ "$view_mode" == "installed" || "$view_mode" == "uninstall" ]]; then
                    [[ ${uninstall_map[$target]} == "true" ]] && uninstall_map[$target]=false || uninstall_map[$target]=true
                else
                    [[ ${selection_map[$target]} == "true" ]] && selection_map[$target]=false || selection_map[$target]=true
                fi
            fi ;;
        $'\n') break ;; 
        $'\x1b') # ARROWS
            read -t 0.05 -k 2 rest
            if [[ "$rest" == "[A" ]]; then (( cursor > 1 )) && (( cursor-- ))
            elif [[ "$rest" == "[B" ]]; then (( cursor++ ))
            fi ;;
        $'\x7f') search_query="${search_query%?}" ;;
        *) [[ "$key" =~ [[:print:]] ]] && search_query+="$key" ;;
    esac
done

# --- 5. Final ---
clear
echo "${BOLD}FINAL OPERATIONS${RESET}"
echo "--------------------------------------------------"

# Ask for the global upgrade
echo -n "Do you want to upgrade all existing apps? (y/N): "
read -k 1 choice
echo ""

echo -e "$fg[cyan]==>$reset_color Refreshing Brew..."
brew update

if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    echo -e "$fg[yellow]==>$reset_color Upgrading all packages..."
    brew upgrade
fi

# 1. Uninstall
to_uninstall=(${(k)uninstall_map[(R)true]})
if (( ${#to_uninstall} > 0 )); then
    echo -e "$fg[red]==>$reset_color Removing selected: ${to_uninstall[*]}"
    brew uninstall ${to_uninstall[@]}
fi

# 2. Install
to_install=(${(k)selection_map[(R)true]})
if (( ${#to_install} > 0 )); then
    echo -e "$fg[cyan]==>$reset_color Installing selected: ${to_install[*]}"
    brew install ${to_install[@]}
fi

# 3. Cleanup
echo -e "$fg[cyan]==>$reset_color Cleaning up..."
brew autoremove
brew cleanup

echo -e "\n$fg[green]✔$reset_color ${BOLD}All done!${RESET}"