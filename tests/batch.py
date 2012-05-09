import sys
import os
from os.path import join, realpath, dirname
from subprocess import Popen, STDOUT
import ConfigParser
from math import sqrt

from joblib import Parallel, delayed

from run import run

SCRIPTDIR=dirname(realpath(__file__))
LEARNERDIR=dirname(SCRIPTDIR)
TLDDIR=join(LEARNERDIR,'TLD')
RESULTSDIR=join(LEARNERDIR,'results')
MATLABDIR=join(SCRIPTDIR,'matlab')

def main(cfgfile, runlabel, ldir=LEARNERDIR, mldir=MATLABDIR, dsdir=TLDDIR,
         resdir=RESULTSDIR):
    outpath = join(resdir,runlabel)
    try:
        os.mkdir(outpath)
    except OSError:
        pass
    config = ConfigParser.ConfigParser()
    config.read(cfgfile)
    datasets = config.get('batch','datasets').split(',')
    runopts = config.items('op')
    runcmd = ['torch','run.lua','--nogui','--tracksingle','--source=dataset']
    for opt,val in runopts:
        if val.strip().lower() in ['true']:
            runcmd.append('--%s' % opt)
        elif val.strip().lower() in ['false']:
            continue
        else:
            runcmd.append('--%s=%s' % (opt,val))

    jobs = (delayed(run)(ldir,runcmd,dsdir,outpath,ds) for ds in datasets)
    Parallel(n_jobs=-1, verbose=5)(jobs)

    compute_results(mldir, datasets, outpath, runlabel)

def compute_results(mldir, datasets, outpath, runlabel):
    mlcmdstr = ("Sequence = {'" + "','".join(datasets) + "'};" + \
               ("InputPath = '%s';" % outpath) + \
               ("Tracker = {'%s'};" % runlabel) + \
               "compute_results;"
               "exit;")
    mlcmd=['matlab','-nodesktop','-nosplash','-r',mlcmdstr]
    with open(join(outpath,'batch.log'),'w') as batchlog:
        child=Popen(mlcmd,cwd=mldir,stdout=batchlog,stderr=STDOUT)
    child.wait()
    child=Popen(['stty','sane'])
    child.wait()

cfgfile = sys.argv[1]
runlabel = sys.argv[-1]
main(cfgfile, runlabel)
