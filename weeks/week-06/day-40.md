# Day 40: Tuning Caddy for the Heavy Lifts

*October 6, 2026*

The perimeter is sealed, the host firewall is locked, and HTTPS works perfectly for photos. But photos are easy. They are 4 MB bursts that transit the proxy in a fraction of a second. Videos are a different beast. Today, I tried uploading a 600 MB 4K video from my phone while connected to the Tailscale DERP relay, forcing the upload to run at a crawl (~1 MB/s). 

The upload failed at the 8-minute mark. 

## Diagnosing the Drop

I dug into the logs to see who killed the connection.

```bash
root@sdrive:~# docker logs sdrive-stack-caddy-1 | grep error
{"level":"error","ts":... ,"msg":"read tcp 10.0.0.3:443->10.0.0.5:41234: i/o timeout"}
```

Caddy terminated the connection. I hadn't explicitly configured read timeouts in the Caddyfile, and the reverse proxy hit a threshold. In networking, slow connections are indistinguishable from Slowloris attacks (where a malicious client sends data at 1 byte per second to tie up server resources). Proxies aggressively drop slow connections to protect themselves.

But for a home backup appliance accessed over a cellular network, a 10-minute upload is normal, not an attack.

## Tuning the Caddyfile

I updated the Caddyfile with two major changes specifically for heavy video workloads.

First, I doubled the `max_size` limit from 512 MB to 1024 MB. A 500 MB limit is easily breached by a 2-minute 4K/60fps video recorded on a modern smartphone. 

Second, I explicitly configured the timeout blocks:

```caddyfile
	request_body {
		max_size 1024MB
	}
	
	timeouts {
		read_body 10m
		read_header 10s
		write 10m
		idle 5m
	}
```

- `read_header 10s`: Headers must still arrive quickly to drop true Slowloris attacks.
- `read_body 10m`: The client has up to 10 minutes to transmit the body payload (the video).
- `write 10m`: The proxy will wait up to 10 minutes for Museum to respond.
- `idle 5m`: Keep-alive connections are preserved for 5 minutes between requests.

I loaded the new configuration:

```bash
root@sdrive:~# docker compose exec -w /etc/caddy caddy caddy reload
2026/10/06 14:15:22.102 INFO  using provided configuration
2026/10/06 14:15:22.105 INFO  reload completed
```
Zero downtime reload.

## The Re-Test: 600 MB over DERP

I retried the exact same 600 MB video upload from the phone, still forced onto the Tailscale DERP relay to simulate the worst-case network environment.

It took 9 minutes and 12 seconds. The progress bar crawled. The connection remained stable the entire time. Caddy held the connection open, streaming the body to Museum, which streamed it into Garage. 

I monitored the memory usage on the board during this massive upload:

```bash
root@sdrive:~# sdrive-golden-signals
[SATURATION] Resource utilization:
  Memory: 485 MB / 3788 MB (12%)
```

Caddy handles streaming beautifully. Because it streams the request body rather than buffering the entire 600 MB in memory, Caddy's memory usage barely fluttered. Museum's memory spiked to ~380 MB (still below the 512 MB container limit), proving the bottleneck identified in Week 04 is manageable for now, provided the user isn't uploading *multiple* 600 MB files simultaneously.

With Caddy properly tuned, the appliance is ready for real-world, unoptimized, massive media libraries.
