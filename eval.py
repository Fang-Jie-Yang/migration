import asyncio
import paramiko
from qemu.qmp import QMPClient
from time import sleep

port     = 22
username = "fjyang"
src_ip   = "128.110.216.31"
dst_ip   = "128.110.216.49"
qmp_port = 4444

key = paramiko.RSAKey.from_private_key_file("/home/student/08/b08902059/.ssh/id_rsa")

#async def temp():
#    src_qmp = QMPClient("src")
#    await src_qmp.connect((src_ip, qmp_port))
#    src_attrs = {'compress-threads' : 1} 
#    await src_qmp.execute('migrate-set-parameters', src_attrs)
#    await src_qmp.execute('migrate-set-capabilities', \
#        {"capabilities": [{"capability": "compress", "state": True}]})
#asyncio.run(temp())
#cmd = """
#lscpu
#ip a
#"""
#_, stdout, stderr = src.exec_command(cmd)
#print(stdout.read().decode())
#_, stdout, stderr = src.exec_command("ip a")
#print(stdout.read().decode())
#src.close()

# return dict: {success, downtime, totaltime, compress rate, rebooting}
async def migrate(src_ip, dst_ip, caps, src_params, dst_params):

    ret = {}
    # set up connections
    key = paramiko.RSAKey.from_private_key_file("/home/student/08/b08902059/.ssh/id_rsa")

    src = paramiko.SSHClient()
    src.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    src.connect(src_ip, port, username, pkey=key)

    dst = paramiko.SSHClient()
    dst.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    dst.connect(dst_ip, port, username, pkey=key)

    # open VMs
    print("opening VMs")
    src_commands = """
    cd /mydata/some-tutorials/files/blk
    sudo nohup ./blk.sh
    """
    dst_commands = """
    cd /mydata/some-tutorials/files/blk
    sudo nohup ./resume-blk.sh
    """
    stdin, stdout, stderr = src.exec_command(src_commands)
    src_err = stderr.read().decode()
    print("=============================================")
    print(src_err)
    stdin, stdout, stderr = dst.exec_command(dst_commands)
    dst_err = stderr.read().decode()
    print("=============================================")
    print(dst_err)
    
    # check if QEMU break
    # note: we only check this error because it needs rebooting to fix
    rebooting = False
    qemu_err = "qemu-system-aarch64: Failed to retrieve host CPU features"
    if qemu_err in src_err or qemu_err in dst_err:
        # reboot to fix qemu
        stdin, stdout, stderr = src.exec_command("sudo reboot")
        stdin, stdout, stderr = dst.exec_command("sudo reboot")
        print("QEMU broken, rebooting")
        src.close()
        dst.close()
        ret["success"] = 0
        ret["downtime"] = -1
        ret["totaltime"] = -1
        ret["compress rate"] = -1
        ret["rebooting"] = True
        return ret
        
    # set attrs
    # note: we ignore errors here 
    print("setting params")
    src_qmp = QMPClient("src")
    await src_qmp.connect((src_ip, qmp_port))
    temp = await src_qmp.execute('migrate-set-capabilities', caps)
    print(temp)
    temp = await src_qmp.execute('migrate-set-parameters', src_params)
    print(temp)
    dst_qmp = QMPClient("dst")
    await dst_qmp.connect((dst_ip, qmp_port))
    temp = await dst_qmp.execute('migrate-set-capabilities', caps)
    print(temp)
    temp = await dst_qmp.execute('migrate-set-parameters', dst_params)
    print(temp)

    # make sure attrs are set correctly
    print("checking params")
    failed = False
    temp = await src_qmp.execute("query-migrate-capabilities")
    print(temp)
    for cap in caps["capabilities"]:
        if cap not in temp:
            print("src caps")
            failed = True
            break
    temp = await src_qmp.execute("query-migrate-parameters")
    print(temp)
    for key in src_params.keys():
        if src_params[key] != temp[key]:
            print("src params")
            failed = True
            break
    temp = await dst_qmp.execute("query-migrate-capabilities")
    print(temp)
    for cap in caps["capabilities"]:
        if cap not in temp:
            print("dst caps")
            failed = True
            break
    temp = await dst_qmp.execute("query-migrate-parameters")
    print(temp)
    for key in dst_params.keys():
        if dst_params[key] != temp[key]:
            print("dst params")
            failed = True
            break
    if failed:
        await src_qmp.execute("quit")
        await dst_qmp.execute("quit")
        src.close()
        dst.close()
        ret["success"] = 0
        ret["downtime"] = -1
        ret["totaltime"] = -1
        ret["compress rate"] = -1
        ret["rebooting"] = False
        return ret

    
    # start migration
    print("starting migration")
    await src_qmp.execute('migrate', { "uri": f"tcp:{dst_ip}:8888" })

    # wait for migration to complete & fetch info
    while True:
        sleep(5)
        result = await src_qmp.execute('query-migrate')
        print(result)
        if 'status' in result:
            if result['status'] == 'completed':
                break

    # make sure attrs are set correctly again
    # note: only count migration with correct attrs as success
    failed = False
    temp = await src_qmp.execute("query-migrate-capabilities")
    for cap in caps["capabilities"]:
        if cap not in temp:
            failed = True
            break
    temp = await src_qmp.execute("query-migrate-parameters")
    for key in src_params.keys():
        if src_params[key] != temp[key]:
            failed = True
            break
    temp = await dst_qmp.execute("query-migrate-capabilities")
    for cap in caps["capabilities"]:
        if cap not in temp:
            failed = True
            break
    temp = await dst_qmp.execute("query-migrate-parameters")
    for key in dst_params.keys():
        if dst_params[key] != temp[key]:
            failed = True
            break
    if failed:
        await src_qmp.execute("quit")
        await dst_qmp.execute("quit")
        src.close()
        dst.close()
        ret["success"] = 0
        ret["downtime"] = -1
        ret["totaltime"] = -1
        ret["compress rate"] = -1
        ret["rebooting"] = False
        return ret

    # close VMs
    # note: need to make sure that we are back to the initial state
    await src_qmp.execute("quit")
    await dst_qmp.execute("quit")

    # return result
    src.close()
    dst.close()
    print(result)
    ret["success"] = 1
    ret["downtime"] = result["downtime"]
    ret["totaltime"] = result["total-time"]
    ret["compress rate"] = -1
    ret["rebooting"] = False
    return ret

caps = {"capabilities": [{"capability": "compress", "state": True}]}
src_params = {'compress-threads' : 1} 
dst_params = {'compress-threads' : 1} 
ret = asyncio.run(migrate(src_ip, dst_ip, caps, src_params, dst_params))
print(ret)
