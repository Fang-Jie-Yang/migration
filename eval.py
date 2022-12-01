import asyncio
import paramiko
from qemu.qmp import QMPClient
from time import sleep

ssh_port     = 22
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

class migration_error(Exception): pass
class qemu_error(Exception): pass
# return dict: {success, downtime, totaltime, compress rate, rebooting}
async def migrate(src_ip, dst_ip, caps, src_params, dst_params):

    ret = {}
    try:
    # Set up connections
        key = paramiko.RSAKey.from_private_key_file("/home/student/08/b08902059/.ssh/id_rsa")
        src_ssh = paramiko.SSHClient()
        src_ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        src_ssh.connect(src_ip, ssh_port, username, pkey=key)
        dst_ssh = paramiko.SSHClient()
        dst_ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        dst_ssh.connect(dst_ip, ssh_port, username, pkey=key)

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
        print(src_err)
        stdin, stdout, stderr = dst_ssh.exec_command(dst_commands)
        dst_err = stderr.read().decode()
        print(dst_err)
        
    # Check if QEMU break
    # note: we only check this error because it needs rebooting to fix
        qemu_err = "qemu-system-aarch64: Failed to retrieve host CPU features"
        if qemu_err in src_err or qemu_err in dst_err:
            raise qemu_error()
        src_ssh.close()
        dst_ssh.close()

    # Wait for VMs to ready
        sleep(15)
            
    # Set capabilities, parameters
    # note: we ignore errors here 
        print("setting params")
        src_qmp = QMPClient("src")
        await src_qmp.connect((src_ip, qmp_port))
        temp = await src_qmp.execute('migrate-set-capabilities', caps)
        temp = await src_qmp.execute('migrate-set-parameters', src_params)
        dst_qmp = QMPClient("dst")
        await dst_qmp.connect((dst_ip, qmp_port))
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
            if 'status' in result:
                if result['status'] == 'completed':
                    break
                if result['status'] == failed:
                    failed = True
                    break
        # FIXME: sometimes it happens, don't know why
        if result["downtime"] == 0 or result["total-time"] == 0:
            failed = True
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
        await src_qmp.execute("quit")
        await dst_qmp.execute("quit")
        sleep(15)

    # Return result
        ret["success"] = 1
        ret["downtime"] = result["downtime"]
        ret["totaltime"] = result["total-time"]
        if "compression" in result:
            ret["compress rate"] = result["compression"]["compression-rate"]
        ret["rebooting"] = False

        await src_qmp.disconnect()
        await dst_qmp.disconnect()

        return ret


    except qemu_error:
    # Reboot to fix qemu
        print("QEMU broken, rebooting")
        stdin, stdout, stderr = src_ssh.exec_command("sudo reboot")
        stdin, stdout, stderr = dst_ssh.exec_command("sudo reboot")
        src_ssh.close()
        dst_ssh.close()
        ret["success"] = 0
        ret["downtime"] = -1
        ret["totaltime"] = -1
        ret["compress rate"] = -1
        ret["rebooting"] = True
        return ret

    except migration_error:
        print("migration failed")
        await src_qmp.execute("quit")
        await dst_qmp.execute("quit")
        ret["success"] = 0
        ret["downtime"] = -1
        ret["totaltime"] = -1
        ret["compress rate"] = -1
        ret["rebooting"] = False
        return ret


caps = {"capabilities": [{"capability": "compress", "state": False}]}
src_params = {'compress-threads' : 1} 
dst_params = {'compress-threads' : 1} 
ret = asyncio.run(migrate(src_ip, dst_ip, caps, src_params, dst_params))
print(ret)
