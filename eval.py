import asyncio
import os
import json
import paramiko
from qemu.qmp import QMPClient
from time import sleep
import logging
import traceback

### Connection Settings ###
ssh_port = 22
qmp_port = 4444
username = "fjyang"
src_ip   = "128.110.216.31"
dst_ip   = "128.110.216.49"
ssh_key  = paramiko.RSAKey.from_private_key_file("/home/student/08/b08902059/.ssh/id_rsa")

### Evaluation Settings ###
rounds_per_setting  = 20
compress_level      = 1
max_bandwidth_MB    = 3
max_bandwidth       = max_bandwidth_MB * 1024 * 1024
compress            = [ False, True, True, True, True ] 
compress_threads    = [ 1    , 8   , 8   , 8   , 8    ] 
decompress_threads  = [ 1    , 1   , 2   , 4   , 8    ]

def reboot(src_ssh, dst_ssh):
    stdin, stdout, stderr = src_ssh.exec_command("sudo reboot")
    stdin, stdout, stderr = dst_ssh.exec_command("sudo reboot")
    src_ssh.close()
    dst_ssh.close()
    hosts_up = False
    while not hosts_up:
        sleep(30)
        src_up  = True if os.system("ping -c 1 " + src_ip) == 0 else False
        dst_up  = True if os.system("ping -c 1 " + dst_ip) == 0 else False
        hosts_up = src_up and dst_up
    # wait for ssh to up
    sleep(30)
    return 

async def check_settings(src_qmp, dst_qmp, cap, src_params, dst_params):
    correct = True
    temp = await src_qmp.execute("query-migrate-capabilities")
    for cap in caps["capabilities"]:
        if cap not in temp:
            correct = False
            break
    temp = await src_qmp.execute("query-migrate-parameters")
    for key in src_params.keys():
        if src_params[key] != temp[key]:
            correct = False
            break
    temp = await dst_qmp.execute("query-migrate-capabilities")
    for cap in caps["capabilities"]:
        if cap not in temp:
            correct = False
            break
    temp = await dst_qmp.execute("query-migrate-parameters")
    for key in dst_params.keys():
        if dst_params[key] != temp[key]:
            correct = False
            break
    return correct

# note: don't use QMP because the connection will drop after 'quit'
#       causing EOFError on QMPClient
# TODO: make this more robust
def shutdown_vm(ssh):
    qmp_cmd  = "{ \'execute\': \'qmp_capabilities\' }"
    qmp_cmd += "\\n{ \'execute\': \'quit\' }"
    ssh_cmd  = f"echo \"{qmp_cmd}\" | nc -N localhost {qmp_port}"
    ssh.exec_command(ssh_cmd)

class migration_error(Exception): pass
class qemu_error(Exception): pass
# return dict: {success, downtime, totaltime, compress rate}
async def migrate(caps, src_params, dst_params):

    global ssh_key
    global src_ip
    global dst_ip

    VMs_up = False
    ret = {}
    try:
    # Set up connections
        src_ssh = paramiko.SSHClient()
        src_ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        src_ssh.connect(src_ip, ssh_port, username, pkey=ssh_key)
        dst_ssh = paramiko.SSHClient()
        dst_ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        dst_ssh.connect(dst_ip, ssh_port, username, pkey=ssh_key)

    # Open VMs
        print("opening VMs")
        src_commands = """
        cd /mydata/some-tutorials/files/blk
        sudo nohup ./blk.sh
        """
        dst_commands = """
        cd /mydata/some-tutorials/files/blk
        sudo nohup ./resume-blk.sh
        """
        stdin, stdout, stderr = src_ssh.exec_command(src_commands)
        src_err = stderr.read().decode()
        #print(src_err)
        stdin, stdout, stderr = dst_ssh.exec_command(dst_commands)
        dst_err = stderr.read().decode()
        #print(dst_err)
        
    # Check if QEMU break
    # note: we only check this error because it needs rebooting to fix
        qemu_err = "qemu-system-aarch64: Failed to retrieve host CPU features"
        if qemu_err in src_err or qemu_err in dst_err:
            raise qemu_error()
        #src_ssh.close()
        #dst_ssh.close()
        VMs_up = True

    # Wait for VMs to ready
        sleep(15)

    # Set up QMP connections
    # note: we ignore errors here 
        src_qmp = QMPClient("src")
        await src_qmp.connect((src_ip, qmp_port))
        dst_qmp = QMPClient("dst")
        await dst_qmp.connect((dst_ip, qmp_port))
            
    # Set capabilities, parameters
    # note: we ignore errors here 
        print("setting params")
        temp = await src_qmp.execute('migrate-set-capabilities', caps)
        temp = await src_qmp.execute('migrate-set-parameters', src_params)
        temp = await dst_qmp.execute('migrate-set-capabilities', caps)
        temp = await dst_qmp.execute('migrate-set-parameters', dst_params)

    # Make sure attrs are set correctly
        print("checking params")
        correct = await check_settings(src_qmp, dst_qmp, caps, src_params, dst_params)
        if not correct:
            raise migration_error()

    # Start migration
        print("starting migration")
        await src_qmp.execute('migrate', { "uri": f"tcp:{dst_ip}:8888" })

    # Wait for migration to complete & fetch info
        failed = False
        while True:
            sleep(15)
            result = await src_qmp.execute('query-migrate')
            print(result)
            if not result:
                failed = True
                break
            if 'status' in result:
                if result['status'] == 'completed':
                    # FIXME: sometimes it happens, don't know why
                    if result and (result["downtime"] == 0 or result["total-time"] == 0):
                        failed = True
                        break
                    else:
                        break
                if result['status'] == 'failed':
                    failed = True
                    break

        if failed:
            raise migration_error()
            
    # Make sure attrs are set correctly again
    # note: only count migration with correct attrs as success
        print("checking params again")
        correct = await check_settings(src_qmp, dst_qmp, caps, src_params, dst_params)
        if failed:
            raise migration_error()

    # Close VMs
    # note: need to make sure that we are back to the initial state
        print("closing VMs")
        shutdown_vm(src_ssh)
        shutdown_vm(dst_ssh)
        VMs_up = False
        sleep(15)

    # Clean up resources
        src_ssh.close()
        dst_ssh.close()

    # Return result
        ret["success"] = 1
        ret["downtime"] = result["downtime"]
        ret["totaltime"] = result["total-time"]
        if "compression" in result:
            ret["compress rate"] = result["compression"]["compression-rate"]
        else:
            ret["compress rate"] = 0
        return ret


    except qemu_error:
    # Reboot to fix qemu
        print("QEMU broken, rebooting")
        reboot(src_ssh, dst_ssh)
        ret["success"] = 0
        ret["downtime"] = -1
        ret["totaltime"] = -1
        ret["compress rate"] = -1
        return ret

    except migration_error:
        print("migration failed")
        shutdown_vm(src_ssh)
        shutdown_vm(dst_ssh)
        src_ssh.close()
        dst_ssh.close()
        ret["success"] = 0
        ret["downtime"] = -1
        ret["totaltime"] = -1
        ret["compress rate"] = -1
        return ret

    except Exception as e:
        print("weird exceptionn")
        logging.error(traceback.format_exc()) 
        if VMs_up:
            shutdown_vm(src_ssh)
            shutdown_vm(dst_ssh)
        src_ssh.close()
        dst_ssh.close()
        ret["success"] = 0
        ret["downtime"] = -1
        ret["totaltime"] = -1
        ret["compress rate"] = -1
        return ret
            

#caps = {"capabilities": [{"capability": "compress", "state": False}]}
#src_params = {'compress-threads' : 1} 
#dst_params = {'compress-threads' : 1} 
#ret = asyncio.run(migrate(src_ip, dst_ip, caps, src_params, dst_params))
#print(ret)

f = open(f"result-bw-{max_bandwidth_MB}-lv-{compress_level}.txt", "w")

for i in range(len(compress)):

    caps   = { "capabilities": [{"capability": "compress", "state": compress[i]}] }
    params = { 
               'compress-threads'   : compress_threads[i], 
               'decompress-threads' : decompress_threads[i],
               'max-bandwidth'      : max_bandwidth
             }
    print(params)
    f.write(json.dumps(params) + '\n')

    sum_downtime      = 0
    sum_totaltime     = 0
    sum_compress_rate = 0
    success           = 0
    t                 = 0
    prev_failed       = False
    continuous_fail   = 0
    while success < rounds_per_setting:
        print("now:", t)
        res = asyncio.run(migrate(caps, params, params))
        print(res)
        success += res["success"]
        if res["success"]:
            sum_downtime      += res["downtime"]
            sum_totaltime     += res["totaltime"]
            sum_compress_rate += res["compress rate"]
            prev_failed        = False
            continuous_fail    = 0
        else:
            if prev_failed:
                continuous_fail += 1
            if continuous_fail >= 10:
                # reboot to fix stuff
                src_ssh = paramiko.SSHClient()
                src_ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                src_ssh.connect(src_ip, ssh_port, username, pkey=ssh_key)
                dst_ssh = paramiko.SSHClient()
                dst_ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                dst_ssh.connect(dst_ip, ssh_port, username, pkey=ssh_key)
                reboot(src_ssh, dst_ssh)
                continuous_fail = 0
            prev_failed = True
            
        t += 1
        sleep(10)
    info_downtime      = f"\tavg downtime      : {sum_downtime      / rounds_per_setting}\n"
    info_totaltime     = f"\tavg totaltime     : {sum_totaltime     / rounds_per_setting}\n"
    info_compress_rate = f"\tavg compress rate : {sum_compress_rate / rounds_per_setting}\n"
    print(info_downtime)
    print(info_totaltime)
    print(info_compress_rate)

    f.write(info_downtime)
    f.write(info_totaltime)
    f.write(info_compress_rate)

        
