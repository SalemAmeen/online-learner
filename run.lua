#!/usr/bin/env torch
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
require 'openmp'

-- do everything in single precision
torch.setdefaulttensortype('torch.FloatTensor')


-- begin global variable definitions

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

op:option{'-N', '--nogui', action='store_true', dest='nogui',
          help='turn off the GUI display (only useful with dataset)'}

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
          help='tracking algorithm: simple, fb, off',
          default='simple'}

op:option{'-A', '--autolearn', action='store_true', dest='autolearn',
          help='turn on autolearning'}

op:option{'-d', '--downsampling', action='store', dest='downs',
          help='downsampling for recognition/processing',
          default=2}

op:option{'-t', '--target', action='store', dest='target',
          help='target to run the code on: cpu | neuflow',
          default='cpu'}

op:option{'-f', '--file', action='store', dest='file',
          help='file to sync memory to',
          default='memory'}

options,args = op:parse()

-- options which are not in the command line yet
-- lower theshold for object recognition
options.recognition_lthreshold = 0.8
-- tracking thesholds (when to drop tracked object)
-- lower threshold for size change in tracker
options.t_sizechange_lthreshold = 0.7
-- upper theshold for size change in tracker
options.t_sizechange_uthreshold = 1.3
-- upper threshold for flow in tracker
options.t_flow_uthreshold = 100
-- class names
options.classes = {'Object 1','Object 2','Object 3',
                   'Object 4','Object 5','Object 6'}


print('e-Lab Online Learner')
print('Initializing...\n')

-- profiler
profiler = xlua.Profiler()

-- load required submodules
state = require 'state'
source = require 'source'
process = require 'process'
tracker = require 'tracker'
-- load gui and display routine, if necessary
if not options.nogui then
   -- setup GUI (external UI file)
   require 'qt'
   require 'qtwidget'
   require 'qtuiloader'
   widget = qtuiloader.load('g.ui')
   painter = qt.QtLuaPainter(widget.frame)

   display = require 'display'
   ui = require 'ui'
end

-- end definition of global variables


-- setup necessary directories
-- save ?
if options.save then
   os.execute('mkdir -p ' .. options.save)
end
-- for memory files
sys.execute('mkdir -p scratch')


-- start execution
print('Initialization finished')
print('Processing...\n')
state.begin()
