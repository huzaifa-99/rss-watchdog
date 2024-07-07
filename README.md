# RSS Watchdog

A simple bash script to aggregate RSS (+ Atom) feeds into a markdown reading checklist. 

This is a hobby project as I needed to get some of my RSS feed subscriptions directly into a reading checklist in a lightweight fashion.

Since the output file is just a simple markdown checklist, it might integrate well with note-taking apps like [Obsidian](https://obsidian.md/), but I haven't tried that.

## Working
1. Modify [rss_subscriptions.csv](./rss_subscriptions.csv) based on your RSS subscriptions (it already has a sample feed - add more feeds as you like). Change the `date_subscribed` field to get content after that date. **Imp: `date_subscribed` should be in ISO 8601 with UTC Time (Zulu)**
2. Make script executable ex: `$ chmod +x ./rss_watchdog.sh`
3. Run it `$ ./rss_watchdog.sh`
4. It will create a `./rss_watchdog.log` file with script logs and a `./reading-list.md` file having subscribed content.

The `./reading-list.md` can be viewed with any markdown viewer (or simple text), and the items in the checklist can be marked completed (when read). ATM the `./reading-list.md` will output to current working dir (it can be changed from the script).

Cron jobs can be set up with `cron` (or any preferred way) to automate fetches.

## Categorizing feeds
The current setup doesn't categorize feeds (as I didn't require that), but adding that shouldn't be too complicated. Just modify the CSV file to make separate reading lists for different feed categories and modify the script to output to those reading lists.

## Compatability
It should work well on any Unix-based environment with core pkgs like `xmllint`, `curl`, `date`, and `grep`.

The only differences will be with the `date` module b/w Linux vs other Unix-based systems. These differences are handled and tested for BSD (macOS) and Linux distributions (Linux, wsl, git bash). For other Unix environments (ex: Solaris), the script exits with a non-zero code if `date` conversion is triggered.