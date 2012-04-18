import sys
import os
from os.path import join, abspath
import ConfigParser
from math import sqrt

from joblib import Parallel, delayed

from run import run

TLDDIR=join('..','TLD')
RESULTSDIR=join('..','results')
LEARNERDIR='..'

def main(cfgfile, runlabel, ldir=LEARNERDIR, dsdir=TLDDIR, resdir=RESULTSDIR):
    ldir=abspath(ldir)
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


cfgfile = sys.argv[1]
runlabel = sys.argv[-1]
main(cfgfile, runlabel)
