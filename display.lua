
-- setup GUI (external UI file)
require 'qt'
require 'qtwidget'
require 'qtuiloader'
widget = qtuiloader.load('g.ui')
painter = qt.QtLuaPainter(widget.frame)

local function display(ui)
   -- resize display ?
   if ui.resize then
      if options.display >= 1 then
         widget.geometry = qt.QRect{x=100,y=100,width=720+options.box/options.downsampling*#ui.classes,height=780}
      else
         widget.geometry = qt.QRect{x=100,y=100,width=720,height=780}
      end
      ui.resize = false
   end

   -- display...
   profiler:start('display')
   painter:gbegin()
   painter:showpage()
   window_zoom = 1

   -- image to display
   local dispimg = ui.rawFrame

   -- overlay track points on input image
   if options.display >= 2 and globs.results[1] then
      -- clone image
      dispimg = dispimg:clone()
      -- disp first result only
      for _,res in ipairs(globs.results) do
         if res.trackPointsP and res.trackPointsP:size(1) > 1 then
            opencv.drawFlowlinesOnImage{pair={res.trackPointsP,res.trackPoints}, image=dispimg}
            dispimg:div(dispimg:max())
         end
      end
   end

   -- display input image
   image.display{image=dispimg,
                 win=painter,
                 zoom=window_zoom}

   -- draw a box around detections
   for _,res in ipairs(globs.results) do
      local color = ui.colors[res.id]
      local legend = res.class
      local w = res.w
      local h = res.h
      local x = res.lx
      local y = res.ty
      painter:setcolor(color)
      painter:setlinewidth(3)
      painter:rectangle(x * window_zoom, y * window_zoom, w * window_zoom, h * window_zoom)
      painter:stroke()
      painter:setfont(qt.QFont{serif=false,italic=false,size=14})
      painter:moveto(x * window_zoom, (y-2) * window_zoom)
      painter:show(legend)
   end

   -- draw a circle around mouse
   _mousetic_ = ((_mousetic_ or -1) + 1) % 2
   if ui.mouse and _mousetic_==1 then
      local color = ui.colors[ui.currentId]
      local legend = 'learning [' .. ui.currentClass .. ']'
      local x = ui.mouse.x
      local y = ui.mouse.y
      local w = options.boxw
      local h = options.boxh
      painter:setcolor(color)
      painter:setlinewidth(3)
      painter:arc(x * window_zoom, y * window_zoom, h/2 * window_zoom, 0, 360)
      painter:stroke()
      painter:setfont(qt.QFont{serif=false,italic=false,size=14})
      painter:moveto((x-options.box/2) * window_zoom, (y-options.box/2-2) * window_zoom)
      painter:show(legend)
   end

   -- display extra stuff
   if options.display >= 1 then
      local size = options.box/options.downsampling

      -- display class distributions
      for id = 1,#ui.classes+1 do
         image.display{image=globs.distributions[id],
                       legend=(id==1 and 'class distributions') or nil,
                       win=painter,
                       x=ui.rawFrame:size(3) + (id-1)*size,
                       y=16,
                       zoom=window_zoom}
      end

      -- disp winner map
      image.display{image=globs.winners,
                    legend='recognition',
                    win=painter,
                    x=ui.rawFrame:size(3),
                    y=globs.distributions:size(2) + 32,
                    min=1, max=#ui.classes+2,
                    zoom=window_zoom*2}

      -- display current protos
      for id = 1,#ui.classes do
         if globs.memory[id] then
            for k,proto in ipairs(globs.memory[id]) do
               image.display{image=proto.patch,
                             legend=(k==1 and 'Obj-'..id) or nil,
                             win=painter,
                             x=ui.rawFrame:size(3) + (id-1)*size,
                             y=(k-1)*size + globs.distributions:size(2)*3+48,
                             zoom=window_zoom}
            end
         end
      end

      -- display RED bounding box, when autolearn is active
      _red_box_ = not _red_box_
      if ui.activeLearning and _red_box_ then
         local x = 4
         local y = 4
         local w = ui.rawFrame:size(3)
         local h = ui.rawFrame:size(2) 
         painter:setcolor('red')
         painter:setlinewidth(8)
         painter:rectangle(x * window_zoom, y * window_zoom, w * window_zoom, h * window_zoom)
         painter:stroke()
      end
   end
   profiler:lap('display')

   -- disp profiler results
   profiler:lap('full-loop')
   local x = 10
   local y = ui.rawFrame:size(2)*window_zoom+20
   painter:setcolor('black')
   painter:setfont(qt.QFont{serif=false,italic=false,size=12})
   painter:moveto(x,y) painter:show('-------------- profiling ---------------')
   profiler:displayAll{painter=painter, x=x, y=y+20, zoom=0.5}

   -- display log
   x = 400
   painter:moveto(x,y) painter:show('-------------- log ---------------')
   for i = 1,#ui.log do
      local txt = ui.log[#ui.log-i+1].str
      local color = ui.log[#ui.log-i+1].color
      y = y + 16
      painter:moveto(x,y)
      painter:setcolor(color)
      painter:show(txt)
      if i == 8 then break end
   end
   painter:gend()

   -- save screen to disk ?
   if options.save then
      _fidx_ = (_fidx_ or 0) + 1
      local t = painter:image():toTensor(3)
      image.save(options.save .. '/' .. string.format('%05d',_fidx_) .. '.png', t)
   end
end

return display
