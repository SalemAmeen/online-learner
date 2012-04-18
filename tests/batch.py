import sys
import os
from os.path import join, abspath
from subprocess import Popen, STDOUT
import ConfigParser
from math import sqrt

from joblib import Parallel, delayed

from run import run

TLDDIR=join('..','TLD')
RESULTSDIR=join('..','results')
LEARNERDIR='..'
MATLABDIR='matlab'

def main(cfgfile, runlabel, ldir=LEARNERDIR, mldir=MATLABDIR, dsdir=TLDDIR,
         resdir=RESULTSDIR):
    ldir=abspath(ldir)
    mldir=abspath(mldir)
    dsdir=abspath(dsdir)
    resdir=abspath(resdir)
    outpath = join(resdir,runlabel)
    os.mkdir(outpath)
    config = ConfigParser.ConfigParser()
    config.read(cfgfile)
    datasets = config.get('batch','datasets').split(',')
    runopts = config.items('op')
    runcmd = ['torch','run.lua','--nogui','--source=dataset']
    for opt,val in runopts:
        try:
            val = config.getboolean('op',opt)
            if val:
                runcmd.append('--%s' % opt)
        except ValueError:
            runcmd.append('--%s=%s' % (opt,val))

    jobs = (delayed(run)(ldir,runcmd,dsdir,outpath,ds) for ds in datasets)
    Parallel(n_jobs=-1, verbose=5)(jobs)

    batchlog = open(join(outpath,'batch.log'),'w')
    mlcmdstr = ("Sequence = {'" + "','".join(datasets) + "'};" + \
               ("InputPath = '%s';" % outpath) + \
               ("Tracker = {'%s'};" % runlabel) + \
               "compute_results;"
               "exit;")
    mlcmd=['matlab','-nodesktop','-nosplash','-r',mlcmdstr]
    child=Popen(mlcmd,cwd=mldir,stdout=batchlog,stderr=STDOUT)

cfgfile = sys.argv[1]
runlabel = sys.argv[-1]
main(cfgfile, runlabel)
