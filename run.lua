#!/usr/bin/env qlua
------------------------------------------------------------
-- xLearner == live/online learning with cortex-like capabilities
-- this script provides a set of functions to experiment
-- with online learning.
--
-- the idea, adapted from LeCun/Kavukcuoglu's
-- original demo (presented during ICCV'09), and from
-- Kalal 2010, "P-N Learning: Bootstrapping Binary Classifiers by
-- Structural Constraints", is as follows:
--
-- + we use a large feature extractor
--   to build up a representation that is more compact
--   and robust to rotation/distortion/translation than the
--   original pixel space
--
-- + we associate vectors in this output space to classes,
--   online (e.g. car, plane, people's names..)
--
-- + in parallel, the stored associations are used to match
--   the content of the live video stream, and infer its class
--
-- + on top of this, spatio-temporal clustering is used to
--   track coherent components over time, and learn from
--   these cues automagically
--
-- Copyright: Clement Farabet, Yann LeCun @ 2011
--

require 'xlua'
require 'nnx'
require 'imgraph'
require 'opencv'
require 'openmp'

-- parse args
op = xlua.OptionParser('%prog [options]')
op:option{'-s', '--source', action='store', dest='source',
          help='image source, can be one of: camera | video | dataset',
          default='camera'}

op:option{'-c', '--camera', action='store', dest='camidx',
          help='if source=camera, you can specify the camera index: /dev/videoIDX',
          default=0}

op:option{'-s', '--save', action='store', dest='save',
          help='path to save video stream'}

op:option{'-v', '--video', action='store', dest='video',
          help='path to video',
          default=''}

op:option{'-r', '--vrate', action='store', dest='fps',
          help='video rate (fps), for video only',
          default=5}

op:option{'-l', '--vlength', action='store', dest='length',
          help='video length (seconds), for video only',
          default=10}

op:option{'-p', '--dspath', action='store', dest='dspath',
          help='path to dataset',
          default=''}

op:option{'-n', '--dsencoding', action='store', dest='dsencoding',
          help='dataset image format',
          default='jpg'}

op:option{'-e', '--encoder', action='store', dest='encoder',
          help='path to encoder module (typically a convnet, sparsifier, ...)',
          default='encoder.net'}

op:option{'-w', '--width', action='store', dest='width',
          help='detection window width',
          default=640}

op:option{'-h', '--height', action='store', dest='height',
          help='detection window height',
          default=480}

op:option{'-b', '--box', action='store', dest='box',
          help='box (training) size',
          default=128}

op:option{'-T', '--tracker', action='store', dest='tracker',
          help='tracking algorithm',
          default='simple'}

op:option{'-A', '--activelearning', action='store_true', dest='activeLearning',
          help='turn on active learning'}

op:option{'-d', '--downsampling', action='store', dest='downsampling',
          help='downsampling for recognition/processing',
          default=2}

op:option{'-t', '--target', action='store', dest='target',
          help='target to run the code on: cpu | neuflow',
          default='cpu'}

op:option{'-f', '--file', action='store', dest='file',
          help='file to sync memory to',
          default='memory'}

options,args = op:parse()

options.boxh = options.box
options.boxw = options.box

-- save ?
if options.save then
   os.execute('mkdir -p ' .. options.save)
end

-- do everything in single precision
torch.setdefaulttensortype('torch.FloatTensor')

-- profiler
profiler = xlua.Profiler()

-- for memory files
sys.execute('mkdir -p scratch')

-- load all submodules
display = require 'display'
ui = require 'ui'
process = require 'process'
ui.start()
