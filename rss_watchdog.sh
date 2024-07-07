#!/bin/bash

# config
RSS_SUBSCRIPTIONS_CSV_FILE="$(pwd)/rss_subscriptions.csv"
READING_LIST_FILE="$(pwd)/reading-list.md"
SCRIPT_NAME=$(basename "$0" .sh)
LOG_FILE="$(pwd)/$SCRIPT_NAME.log"
TMP_FILE="$(pwd)/$SCRIPT_NAME.tmp"
SKIP_CSV_HEADERS=true

log() {
    local message="$1"
    echo "$message" # also log to terminal
    # maybe handle error logs with `[Error]` if needed
    echo "[Info]: $(date -u +"%Y-%m-%dT%H:%M:%SZ") - $message" >> "$LOG_FILE"
}
log "🔍 RSS Watchdog looking for new content"

cleanup() {
    log "received SIGINT/SIGTERM, cleaning up..."
    exit 0
}
trap cleanup SIGINT SIGTERM # trap SIGINT and SIGTERM signals to call cleanup function

# validate config
if [ ! -e "$RSS_SUBSCRIPTIONS_CSV_FILE" ]; then
    log "RSS subscription file not found. Terminating..."
    exit 1;
fi

# validate required commands
required_cmds=("xmllint" "curl" "grep" "date")
for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        log "$cmd is not installed."
        exit 1
    fi
done

# returns date with utc time (zulu) ex: YYYY-MM-DDTHH:MM:SS.000Z
date_to_iso_8061() {
    local date="$1"

    case "$OSTYPE" in # $OSTYPE is set by bash, based on current OS
        linux*|msys*|cygwin*)
            # "Linux / WSL / MSYS / MinGW / Git Bash"
            unix_timestamp=$(date -d "$date" +"%s")
            iso_date=$(date -u -d "@$unix_timestamp" +"%Y-%m-%dT%H:%M:%S.000Z")
            echo $iso_date
            ;;
        darwin*|bsd*)
            # "macOS / BSD" 
            case "$date" in
                *GMT) 
                    # rfc822/rfc1123 format
                    unix_timestamp=$(date -j -f "%a, %d %b %Y %T %Z" "$date" +"%s")
                    ;;
                *)
                    # assuming iso8601 format (with utc offset ex: YYYY-MM-DDTHH:MM:SS+00:00)
                    date_without_offset=$(echo "$date" | sed 's/+00:00//')
                    unix_timestamp=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$date_without_offset" +"%s")
                    ;;
            esac

            # convert to iso
            iso_date=$(date -u -r "$unix_timestamp" +"%Y-%m-%dT%H:%M:%S.000Z")
            echo $iso_date
            ;;
        *)        
            # treating unknown OS as not supported and halting scrpit (solaris date module might work but i didn't/couldn't test)
            log "date module not supported for current OS = $OSTYPE"
            exit 1
            ;;
    esac
}

# loop over csv
while IFS= read -r line || [[ -n $line ]]; do
    # skip headers
    if $SKIP_CSV_HEADERS; then
        SKIP_CSV_HEADERS=false
        continue  
    fi

    # read columns (assuming the format is as described and csv data is valid)
    IFS=, read -r feed_url date_subscribed topics <<< "$line" # expecting date_subscribed to be iso8601 format with utc time (zulu)
    
    # fetch rss feed for $feed_url + handle error cases
    rss_content=$(curl -s "$feed_url")
    if [ $? -ne 0 ]; then
        log "Failed to fetch data from $feed_url"
        continue
    elif [ -z "$rss_content" ]; then
        log "RSS fetched from $feed_url is empty."
        continue
    fi
    echo $rss_content > $TMP_FILE # hack: xmllint isn't reading correctly from curl response, saving then reading from tmp file does the trick
    rss_content=$(cat $TMP_FILE)
    if ! xmllint --noout $TMP_FILE >/dev/null 2>&1; then
        log "RSS feed from $feed_url is invalid XML."
        rm -rf $TMP_FILE
        continue
    fi
    rm -rf $TMP_FILE

    # detect feed type and extract entries/blog
    if echo "$rss_content" | xmllint --xpath '//*[local-name()="feed"]' - >/dev/null 2>&1; then
        log "Detected application/atom+xml feed for $feed_url"
        is_atom_feed=true
        entries=$(echo "$rss_content" | xmllint --xpath '//*[local-name()="entry"]' -)
    elif echo "$rss_content" | grep -q '<rss'; then
        log "Detected application/rss+xml feed for $feed_url"
        is_atom_feed=false
        entries=$(echo "$rss_content" | xmllint --xpath '//item' -)
    else
        log "Unknown feed format for $feed_url"
        continue
    fi

    # add each feed item as an entry to reading list
    while IFS= read -r entry; do
        # sanitize rss data based on format
        if $is_atom_feed; then
            title=$(echo "$entry" | xmllint --xpath '//*[local-name()="title"]/text()' - 2>/dev/null)
            link=$(echo "$entry" | xmllint --xpath 'string(//*[local-name()="link"]/@href)' - 2>/dev/null)
            # rss feeds use RFC 822 (Internet message format) for dates -- also called "RFC 822 Date and Time Specification" ex: "Tue, 07 Jul 2024 14:30:00 +0000"
            pub_date=$(echo "$entry" | xmllint --xpath '//*[local-name()="published"]/text()' - 2>/dev/null)
            if [ -z "$pub_date" ]; then
                log "Skipping $link as it doesn't have publish date"
                continue;
            fi
        else
            title=$(echo "$entry" | xmllint --xpath 'string(//title)' - 2>/dev/null)
            link=$(echo "$entry" | xmllint --xpath 'string(//link)' - 2>/dev/null)
            # atom feeds use ISO 8601 for dates ex: "2024-07-07T14:30:00Z"
            pub_date=$(echo "$entry" | xmllint --xpath 'string(//pubDate)' - 2>/dev/null)
            if [ -z "$pub_date" ]; then
                log "Skipping $link as it doesn't have publish date"
                continue;
            fi
        fi
        
        # prepare item for reading list (using markdown checklist format)
        iso8061_timestamp=$(date_to_iso_8061 "$pub_date")
        listItem="- [ ] \`$iso8061_timestamp\`: [$title]($link)"

        # add item to reading list (if not already in reading list)
        if ! grep -F -e $link $READING_LIST_FILE >/dev/null; then
            # only add items if they are after my rss subscription date
            if [[ "$iso8061_timestamp" < "$date_subscribed" ]] ; then
                # do nothing
                log "Skipping $link as i subscribed on $date_subscribed while publish date is $iso8061_timestamp"
                continue
            fi

            # publish date is after or equal to subscribed date - add item to list
            echo "$listItem" >> $READING_LIST_FILE
            log "Adding $link in reading list"
        else
            log "Skipping $link as its already in reading list"
        fi
    done <<< "$entries";
done < "$RSS_SUBSCRIPTIONS_CSV_FILE";

log "RSS Watchdog says goodbye 👋"