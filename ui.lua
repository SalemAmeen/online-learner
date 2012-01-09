
-- global ui object
local ui = {}

-- setup gui
local timer = qt.QTimer()
timer.interval = 10
timer.singleShot = true
timer:start()
qt.connect(timer,
           'timeout()',
           function()
              ui.threshold = widget.verticalSlider.value / 1000
              process(ui)
              display(ui)
              timer:start()
           end)
ui.timer = timer

-- connect all buttons to actions
ui.classes = {widget.pushButton_1, widget.pushButton_2, widget.pushButton_3, 
               widget.pushButton_4, widget.pushButton_5, widget.pushButton_6}

-- colors
ui.colors = {'blue', 'green', 'orange', 'cyan', 'purple', 'brown', 'gray', 'red', 'yellow'}

-- set current class to learn
ui.currentId = 1
ui.currentClass = ui.classes[ui.currentId].text:tostring()
for i,button in ipairs(ui.classes) do
   qt.connect(qt.QtLuaListener(button),
              'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
              function (...)
                 ui.currentId = i
                 ui.currentClass = ui.classes[ui.currentId].text:tostring()
              end)
end

-- reset
qt.connect(qt.QtLuaListener(widget.pushButton_forget),
           'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
           function (...)
              ui.forget = true
           end)

-- resize
options.display = 1 -- 3 levels (0=nothing, 1=protos, 2=track points)
ui.resize = true
qt.connect(qt.QtLuaListener(widget.pushButton_disp),
           'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
           function (...)
              options.display = options.display + 1
              if options.display > 2 then options.display = 0 end
              ui.resize = true
           end)

-- learn on/off
ui.activeLearning = false
qt.connect(qt.QtLuaListener(widget.pushButton_learn),
           'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
           function (...)
              ui.activeLearning = not ui.activeLearning
              if ui.activeLearning then
                 ui.logit('auto-learning is on !')
              else
                 ui.logit('auto-learning off...')
              end
           end)

-- save session
ui.save = false
qt.connect(qt.QtLuaListener(widget.pushButton_save),
           'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
           function (...)
              ui.save = true
          end)

-- load session
ui.load = false
qt.connect(qt.QtLuaListener(widget.pushButton_load),
           'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
           function (...)
              ui.load = true
          end)

-- connect mouse pos
widget.frame.mouseTracking = true
qt.connect(qt.QtLuaListener(widget.frame),
           'sigMouseMove(int,int,QByteArray,QByteArray)',
           function (x,y)
              ui.mouse = {x=x,y=y}
           end)

-- issue learning request
qt.connect(qt.QtLuaListener(widget),
           'sigMousePress(int,int,QByteArray,QByteArray,QByteArray)',
           function (...)
              if ui.mouse then
                 ui.learn = {x=ui.mouse.x, y=ui.mouse.y, id=ui.currentId, class=ui.currentClass}
              end
           end)

widget.windowTitle = 'Live Learning'
widget:show()

-- provide log
ui.log = {}
ui.logit = function(str, color) table.insert(ui.log,{str=str, color=color or 'black'}) end

-- return ui
return ui
