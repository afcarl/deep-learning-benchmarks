require 'sys'
require 'optim'
require 'cutorch'


local opts = require 'opts'
local opt = opts.parse(arg)

-- require 'fbcunn'
-- require 'nnbhwd' -- not compiling anymore, file an issue
local nets = {}
nets[#nets+1] = require 'alexnet'
-- nets[#nets+1] = require 'overfeat'
-- nets[#nets+1] = require 'vgg_a'
--nets[#nets+1] = require 'googlenet'

local libs = {}
-- libs[#libs+1] = {fbnn.SpatialConvolution, cudnn.SpatialMaxPooling, cudnn.ReLU, 'BDHW', 'fbnn'}
-- libs[#libs+1] = {nn.SpatialConvolutionMM, nn.SpatialMaxPooling, nn.ReLU, 'BDHW', 'nn'}
-- libs[#libs+1] = {nn.SpatialConvolutionBHWD, nn.SpatialMaxPoolingBHWD, nn.ReLU, 'BHWD', 'nnBHWD'}

if opt.deviceId >= 0 then
   require 'cunn'
   require 'cudnn'
   cudnn.benchmark = true -- run manual auto-tuner provided by cudnn
   cudnn.verbose = false
   cutorch.setDevice(opt.deviceId+1)
   print('Running on device: ' .. cutorch.getDeviceProperties(cutorch.getDevice()).name)
   libs[#libs+1] = {cudnn.SpatialConvolution, cudnn.SpatialMaxPooling, cudnn.ReLU, 'BDHW', 'cudnn'}
else
   require 'nn'
   libs[#libs+1] = {nn.SpatialConvolution, nn.SpatialMaxPooling, nn.ReLU, 'BDHW', 'nn'}
end

steps = opt.nIterations-- nb of steps in loop to average perf
nDryRuns = opt.nEpochs 

function makeInput(config, size)
   local layout = config[4]
   local osize, lsize
   if layout == 'BDHW' then
      osize = size
   elseif layout == 'DHWB' then
      osize = {size[2],size[3],size[4],size[1]}
   elseif layout == 'BHWD' then
      osize = {size[1], size[3], size[4], size[2]}
   end
   lsize = size[1]
   return torch.randn(torch.LongStorage(osize)), torch.ones(lsize)
end

for i=1,#nets do
   for j=1,#libs do
      collectgarbage()
      local model,model_name,size = nets[i](libs[j])
      local paramx, paramdx = model:getParameters()
      local ax, adx         = model:parameters()
      print('Model Parameters: ', paramx:nElement())
      print('All shape: ', ax)

      size[1] = opt.batchSize
      local input, label
      local inputData 
      local criterion

      if opt.deviceId >= 0 then
          model = model:cuda()
          inputData, label = makeInput(libs[j],size)
          label = label:cuda()
          input = torch.Tensor(inputData:size()):float():cuda()
          criterion = nn.ClassNLLCriterion():cuda()
      else
          inputData, label = makeInput(libs[j],size)
          input = torch.Tensor(inputData:size()):float()
          criterion = nn.ClassNLLCriterion()
      end
      local lib_name = libs[j][5]
      print('ModelType: ' .. model_name, 'Kernels: ' .. lib_name,
            'Input shape: ' .. input:size(1) .. 'x' .. input:size(2) ..
               'x' .. input:size(3) .. 'x' .. input:size(4))

      -- dry-run
      for i=1,nDryRuns do
         model:zeroGradParameters()
         input:copy(inputData)
         local output = model:forward(input)
         local err    = criterion:forward(output, label)
         local gradOutput = criterion:backward(output, label)
         local gradInput  = model:backward(input, gradOutput)

         --local output = model:updateOutput(input)
         --local gradInput = model:updateGradInput(input, output)
         --model:accGradParameters(input, output)
         paramx:add(paramdx:mul(-opt.LR))

         cutorch.synchronize()
         collectgarbage()
      end

      local tmf, tmbi, tmbg, tmcopy, tmzero
        
      collectgarbage()
      sys.tic()
      for t = 1, steps do
          input:copy(inputData)
      end
      cutorch.synchronize()
      tmcopy = sys.toc()/steps
      print(string.format("%-30s %25s %10.2f", lib_name, ':Copy data:', tmcopy*1000))


      collectgarbage()
      sys.tic()
      for t = 1,steps do
         output = model:forward(input)
         err    = criterion:forward(output, label)
      end
      cutorch.synchronize()
      tmf = sys.toc()/steps
      print(string.format("%-30s %25s %10.2f", lib_name, ':forward:', tmf*1000))


      collectgarbage()
      sys.tic()
      for t = 1,steps do
         gradOutput = criterion:backward(output, label)
         gradInput  = model:backward(input, gradOutput)
      end
      cutorch.synchronize()
      tmbi = sys.toc()/steps
      print(string.format("%-30s %25s %10.2f", lib_name, ':backward:', tmbi*1000))

      collectgarbage()
      sys.tic()
      for t = 1,steps do
         --paramx:add(paramdx:mul(-opt.LR))
         pcall(function() model:accGradParameters(input, output) model:updateParameters(opt.LR) end)
      end
      cutorch.synchronize()
      tmbg = sys.toc()/steps
      print(string.format("%-30s %25s %10.2f", lib_name, ':update:', tmbg*1000))


      sys.tic()
      for t = 1,steps do
          model:zeroGradParameters()
      end
      cutorch.synchronize()
      tmzero = sys.toc()/steps
      print(string.format("%-30s %25s %10.2f", lib_name, ':Reset gradient:', tmzero*1000))



      print(string.format("%-30s %25s %10.2fms", lib_name, ':TOTAL:', (tmcopy+tmf+tmbi+tmbg+tmzero)*1000))
      print(string.format(" | Epoch: [][]    Time %10.6f", (tmcopy+tmf+tmbi+tmbg+tmzero)))
      print()
   end
end

print('')
