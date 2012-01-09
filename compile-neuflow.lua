
-- instantiate neuFlow
neuFlow = NeuFlow()

-- create a new object to compute the encoder
local encoder_hw = {
   forward = function(self, input)
                -- for the first call, implement and load the code on neuFlow
                if not self.running then
                   -- divide network into sub-networks
                   self.normer = encoderm.modules[1]
                   self.network = nn.Sequential()
                   for i = 2,5 do
                      self.network:add(encoderm.modules[i])
                   end
                   self.maxpooler = nn.Sequential()
                   for i = 6,#encoderm.modules do
                      self.maxpooler:add(encoderm.modules[i])
                   end
                   -- implement networks
                   neuFlow:beginLoop('main') do
                      local input_dev = neuFlow:copyFromHost(input)
                      local output_dev = neuFlow:compile(self.network, input_dev)
                      self.outputhw = neuFlow:copyToHost(output_dev)
                   end neuFlow:endLoop('main')
                   -- load code
                   neuFlow:loadBytecode()
                   self.running = true
                end
                -- then transfer data, and retrieve results
                self.normed = self.normer:forward(input)
                neuFlow:copyToDev(self.normed)
                neuFlow:copyFromDev(self.outputhw)
                self.output = self.maxpooler:forward(self.outputhw)
                return self.output
             end
}
return encoder_hw
