
require 'inline'

-- some coroutines
local c = {}

-- some defines
inline.preamble [[
      #define max(a,b)  ((a)>(b) ? (a) : (b))
      #define abs(a)    (a) < 0 ? -(a) : (a)
      #define square(a) (a)*(a)
]]

-- match a prototype against a prediction field
c.match = inline.load [[
      // get args
      const void* torch_Tensor_id = luaT_checktypename2id(L, "torch.FloatTensor");
      THFloatTensor *input = luaT_checkudata(L, 1, torch_Tensor_id);
      THFloatTensor *proto = luaT_checkudata(L, 2, torch_Tensor_id);
      THFloatTensor *output = luaT_checkudata(L, 3, torch_Tensor_id);

      // get raw pointers
      float *input_data = THFloatTensor_data(input);
      float *proto_data = THFloatTensor_data(proto);
      float *output_data = THFloatTensor_data(output);

      // dims
      int ichannels = input->size[0];
      int iheight = input->size[1];
      int iwidth = input->size[2];
      int owidth = output->size[1];

      // compare proto to input
      int x,y,k;
      for (x=0; x<iwidth; x++) {
         for (y=0; y<iheight; y++) {
            float dist = 0;
            for (k=0; k<ichannels; k++) {
               dist += abs(input_data[(y+k*iheight)*iwidth+x] - proto_data[k]);
            }
            dist /= ichannels;
            float prob = exp(-dist);
            output_data[y*owidth+x] = max(prob, output_data[y*owidth+x]);
         }
      }

      // done
      return 1;
]]

-- detect blobs in a map, and return a list of bounding boxes {lx,rx,ty,by}
-- the map is assumed to be a map of connected components (e.g. each component has a
-- unique value)
-- a second arg 'ignore' can be used to ignore a value (typically the background)
c.getblobs = inline.load [[
      // get args
      const void* torch_FloatTensor_id = luaT_checktypename2id(L, "torch.FloatTensor");
      const void* torch_LongTensor_id = luaT_checktypename2id(L, "torch.LongTensor");
      THFloatTensor *input = luaT_checkudata(L, 1, torch_FloatTensor_id);
      THLongTensor *ids = luaT_checkudata(L, 2, torch_LongTensor_id);
      float ignore = 0;
      if (lua_isnumber(L, 3)) ignore = lua_tonumber(L, 3);

      // get raw pointers
      float *input_data = THFloatTensor_data(input);
      long *ids_data = THLongTensor_data(ids);

      // dims
      int iheight = input->size[0];
      int iwidth = input->size[1];

      // create table for results
      lua_newtable(L);                       // boxes = {}
      int boxes = lua_gettop(L);

      // loop over pixels
      int x,y;
      int val,id;
      int idx = 0;
      for (x=0; x<iwidth; x++) {
         for (y=0; y<iheight; y++) {
            val = input_data[y*iwidth+x];
            id = ids_data[y*iwidth+x];
            if (id != ignore) {
               // is this hash already registered ?
               lua_rawgeti(L,boxes,val);     // boxes[val]
               if (lua_isnil(L,-1)) {        // boxes[val] == nil ?
                  lua_pop(L,1);
                  // create new entry
                  lua_newtable(L);           // entry = {}
                  int entry = lua_gettop(L);
                  lua_pushnumber(L, x+1);
                  lua_rawseti(L,entry,1);    // entry[1] = x   -- left
                  lua_pushnumber(L, x+1);
                  lua_rawseti(L,entry,2);    // entry[2] = x   -- right
                  lua_pushnumber(L, y+1);
                  lua_rawseti(L,entry,3);    // entry[3] = y   -- top
                  lua_pushnumber(L, y+1);
                  lua_rawseti(L,entry,4);    // entry[4] = y   -- bottom
                  lua_pushnumber(L, id);
                  lua_rawseti(L,entry,5);    // entry[5] = id  -- id
                  // store entry
                  lua_rawseti(L,boxes,val);  // boxes[val] = entry
               } else {
                  // retrieve entry                  
                  int entry = lua_gettop(L); // get boxes[val]
                  // lx
                  lua_rawgeti(L, entry, 1);
                  long lx = lua_tonumber(L, -1); // lx = boxes[val][1]
                  lua_pop(L, 1);
                  if (x < lx) {
                     lua_pushnumber(L, x+1);
                     lua_rawseti(L, entry, 1);  // boxes[val][1] = x
                  }
                  // rx
                  lua_rawgeti(L, entry, 2);
                  long rx = lua_tonumber(L, -1); // rx = boxes[val][2]
                  lua_pop(L, 1);
                  if (x > rx) {
                     lua_pushnumber(L, x+1);
                     lua_rawseti(L, entry, 2);  // boxes[val][2] = x
                  }
                  // ty never changes, by can be updated each time
                  lua_pushnumber(L, y+1);
                  lua_rawseti(L, entry, 4);  // boxes[val][4] = y
                  lua_pop(L,1);
               }
            }
         }
      }

      // return boxes
      return 1;
]]

-- return package
return c