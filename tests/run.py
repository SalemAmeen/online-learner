import os
from subprocess import Popen, STDOUT

def run(ldir,runcmd,dsdir,outpath,dataset):
    dspath = os.path.join(dsdir,dataset)
    dsoutput = os.path.join(outpath,'%s.txt' % dataset)        
    dslog = os.path.join(outpath, '%s.log' % dataset)
    dscmd = list(runcmd)
    dscmd.append('--dspath=%s' % dspath)
    dscmd.append('--dsoutput=%s' % dsoutput)
    logfile = open(dslog,'w')
    logfile.write(str(dscmd))
    child=Popen(dscmd,cwd=ldir,stdout=logfile,stderr=STDOUT)
    child.wait()
    logfile.close()
