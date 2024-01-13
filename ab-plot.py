import sys
import matplotlib.pyplot as plt
import pandas as pd

log = pd.read_csv(sys.argv[1], sep='\t', header=0)

log['start_msec'] = log['seconds']*1000 + log['milliseconds']
log['req_msec'] = log['start_msec'] + log['ttime']
log['req_msec'] = log['req_msec'] - log['req_msec'].min()

a = log['req_msec'].sort_values()
b = log['req_msec'].sort_values()
b = b.shift(periods=1)
c = a-b

print(f'downtime: {c.max()}')

window = 1000
step = 20
total = 20000

down_at = a[c.argmax()]
print(down_at)
start = max(down_at - total // 2, 0)
end = min(down_at + total // 2, log['req_msec'].max())
timestamp = []
req = []
for t in range(start, end, step):
    timestamp.append(t+window//2)
    req.append(log['req_msec'].between(t, t+window, inclusive='left').sum() / (window/1000))

Graph1 = plt.figure(1)
req_per_sec= Graph1.add_subplot(111)

req_per_sec.set_title('Result of migrating a running web server VM')
req_per_sec.set_xlabel('Elapsed time (ms)')
req_per_sec.set_ylabel('Requests per second')
req_per_sec.xaxis.grid()
req_per_sec.yaxis.grid()
req_per_sec.plot(timestamp,req)

plt.savefig(input())
