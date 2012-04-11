--functions for manipulating ui
local display = {}

-- function to update display
function display.update()
   -- resize display ?
   if ui.resize then
      if options.display >= 1 then
         widget.geometry = qt.QRect{x=100,y=100,width=720+options.boxw/options.downs*#ui.classes,height=780}
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
   local dispimg = state.rawFrame

   -- overlay track points on input image
   if options.display >= 2 and state.results[1] then
      -- clone image
      dispimg = dispimg:clone()
      -- disp first result only
      for _,res in ipairs(state.results) do
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

   if options.source == 'dataset' then
      -- draw a box around ground truth
      local gt = source.gt
      local w = gt.rx - gt.lx
      local h = gt.by - gt.ty
      local x = gt.lx
      local y = gt.ty
      painter:setcolor('green')
      painter:setlinewidth(3)
      painter:rectangle(x * window_zoom, y * window_zoom, w * window_zoom, h * window_zoom)
      painter:stroke()
      painter:setfont(qt.QFont{serif=false,italic=false,size=14})
      painter:moveto(x * window_zoom, (y-2) * window_zoom)
      painter:show('Ground truth')
   end

   -- draw a box around detections
   for _,res in ipairs(state.results) do
      local color = ui.colors[res.id]
      local legend = res.class
      local w = res.w
      local h = res.h
      local x = res.lx
      local y = res.ty
      painter:setcolor(color)
      if(res.source==1)then
         painter:setlinewidth(3)
      end
      if(res.source>2) then
         painter:setlinewidth(6)
      end
		
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
      painter:moveto((x-options.boxw/2) * window_zoom, (y-options.boxh/2-2) * window_zoom)
      painter:show(legend)
   end

   -- display extra stuff
   if options.display >= 1 then
      local sizew = options.boxw/options.downs
      local sizeh = options.boxh/options.downs

      -- display class distributions
      for id = 1,#ui.classes+1 do
         image.display{image=state.distributions[id],
                       legend=(id==1 and 'class distributions') or nil,
                       win=painter,
                       x=state.rawFrame:size(3) + (id-1)*sizew,
                       y=16,
                       zoom=window_zoom}
      end

      -- disp winner map
      image.display{image=state.winners,
                    legend='recognition',
                    win=painter,
                    x=state.rawFrame:size(3),
                    y=state.distributions:size(2) + 32,
                    min=1, max=#ui.classes+2,
                    zoom=window_zoom*2}

      -- display current protos
      for id = 1,#ui.classes do
         if state.memory[id] then
            for k,proto in ipairs(state.memory[id]) do
               image.display{image=proto.patch,
                             legend=(k==1 and 'Obj-'..id) or nil,
                             win=painter,
                             x=state.rawFrame:size(3) + (id-1)*sizew,
                             y=(k-1)*sizeh + state.distributions:size(2)*3+48,
                             zoom=window_zoom}
            end
         end
      end

      -- display RED bounding box, when autolearn is active
      _red_box_ = not _red_box_
      if state.autolearn and _red_box_ then
         local x = 4
         local y = 4
         local w = state.rawFrame:size(3)
         local h = state.rawFrame:size(2)
         painter:setcolor('red')
         painter:setlinewidth(8)
         painter:rectangle(x * window_zoom, y * window_zoom, w * window_zoom, h * window_zoom)
         painter:stroke()
      end

      -- update threshold
      state.threshold = widget.verticalSlider.value / 1000
   end
   ui.proc()
   profiler:lap('display')
end


function display.results()
   -- disp profiler results
   local x = 10
   local y = state.rawFrame:size(2)*window_zoom+20
   painter:setcolor('black')
   painter:setfont(qt.QFont{serif=false,italic=false,size=12})
   painter:moveto(x,y) painter:show('-------------- profiling ---------------')
   profiler:displayAll{painter=painter, x=x, y=y+20, zoom=0.5}

   -- display log
   display.log()

   -- save screen to disk
   if options.save then
      display.save()
   end
end

function display.log()
   x = 400
   local y = state.rawFrame:size(2)*window_zoom+20
   painter:moveto(x,y) painter:show('-------------- log ---------------')
   for i = 1,#state.log do
      local txt = state.log[#state.log-i+1].str
      local color = state.log[#state.log-i+1].color
      y = y + 16
      painter:moveto(x,y)
      painter:setcolor(color)
      painter:show(txt)
      if i == 8 then break end
   end
   painter:gend()
end

function display.save()
   display._fidx_ = (display._fidx_ or 0) + 1
   local t = painter:image():toTensor(3)
   image.save(options.save .. '/'
              .. string.format('%05d',display._fidx_) .. '.png', t)
end

-- display loop for after video/dataset has finished
local timer = qt.QTimer()
timer.interval = 10
timer.singleShot = true
function display.begin(loop)
   local function finishloop()
      if state.finished then
         state.finish()
         qt.disconnect(timer,
                       'timeout()',
                       finishloop)
         qt.connect(timer,
                    'timeout()',
                    function() 
                       display.update()
                       display.log()
                       timer:start()
                    end)
         timer:start()
      else
         loop()
         timer:start()
      end
   end
   qt.connect(timer,
              'timeout()',
              finishloop)
   timer:start()      
end


return display
