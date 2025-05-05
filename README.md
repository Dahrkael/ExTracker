# ExTracker
The Bittorrent Tracker made in Elixir

👷‍♂️This project is a Work In Progress and not ready for production usage

## Features
Implementation Legend: 
🔲 Not Yet 🔰 Partially ✅ Done ❌ Won't do

### Tracker-related BitTorrent Enhancement Proposals

#### Final and Active Process BEPs
- ✅ **BEP 0:** [The BitTorrent Protocol Specification](https://www.bittorrent.org/beps/bep_0003.html)
#### Accepted BEPs
- ✅ **BEP 15:** [UDP Tracker Protocol](https://www.bittorrent.org/beps/bep_0015.html)
- ✅ **BEP 23:** [Tracker Returns Compact Peer Lists](https://www.bittorrent.org/beps/bep_0023.html)
- 🔲 **BEP 27:** [Private Torrents](https://www.bittorrent.org/beps/bep_0027.html)
#### Draft BEPs
- 🔲 **BEP 7:** [IPv6 Tracker Extension](https://www.bittorrent.org/beps/bep_0007.html)
- ✅ **BEP 24:** [Tracker Returns External IP](https://www.bittorrent.org/beps/bep_0024.html)
- 🔲 **BEP 31:** [Tracker Failure Retry Extension](https://www.bittorrent.org/beps/bep_0031.html)
- 🔲 **BEP 41:** [UDP Tracker Protocol Extensions](https://www.bittorrent.org/beps/bep_0041.html)
- 🔰 **BEP 48:** [Tracker Protocol Extension: Scrape](https://www.bittorrent.org/beps/bep_0048.html)
- ✅ **BEP 52:** [The BitTorrent Protocol Specification v2](https://www.bittorrent.org/beps/bep_0052.html)
#### Deferred BEPs
- ❌ **BEP 8:** [Tracker Peer Obfuscation](https://www.bittorrent.org/beps/bep_0008.html)

### Non-BEP Features
- 🔲 HTTPS support
- 🔲 Database backups to disk
- ❌ WebTorrent
- 🔲 Infohash whitelist/blacklist
- 🔲 Peer management (interval enforcement, banning, etc)
- **Feel free to propose features in the [Issues](https://github.com/Dahrkael/ExTracker/issues)**

## Interesting bit of Technical Information

- Both the HTTP(S) and UDP frontends scale linearly with the number of cpu cores. The more the better!
- Each swarm (torrent) is stored in-memory for fast access. Heres a table showing how much memory a swarm uses based on the number of peers registered in it:

| Peer Count | Total Memory |
|:-----------|:-------------|
| 10         | 4.65 KB      |
| 100        | 25.04 KB     |
| 1000       | 246.99 KB    |
| 10000      | 2.29 MB      |
| 100000     | 22.90 MB     |
| 1000000    | 228.90 MB    |
