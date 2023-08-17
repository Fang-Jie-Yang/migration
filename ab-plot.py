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

frame_size = 200
frame_shift = 20

end_time = log['req_msec'].max()

timestamp = []
req = []

for t in range(0, 30000, frame_shift):
    timestamp.append(t+frame_size//2)
    req.append(log['req_msec'].between(t, t+frame_size, inclusive='left').sum() / (frame_size/1000))

Graph1 = plt.figure(1)
req_per_sec= Graph1.add_subplot(111)

req_per_sec.set_title('Result of migrating a running web server VM')
req_per_sec.set_xlabel('Elapsed time (ms)')
req_per_sec.set_ylabel('Requests per second')
req_per_sec.xaxis.grid()
req_per_sec.yaxis.grid()
req_per_sec.plot(timestamp,req)

plt.savefig(input())
