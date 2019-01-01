classdef Simultaneous < handle
  %COLLOCATION Collocation discretization of OCP to NLP
  %   Discretizes continuous OCP formulation to be solved as an NLP
  
  properties
    nlpFun
  end
  
  properties(Access = private)
    lowerBounds
    upperBounds
    scalingMin
    scalingMax
    integratorFun
    ocpHandler
    N
    nx
    ni
    nu
  end
  
  methods
    
    function self = Simultaneous(system,integrator,ocpHandler,N)
      
      self.N = N;
      self.nx = system.nx;
      self.ni = integrator.nvars;
      self.nu = system.nu;
      self.np = system.np;
      
      self.ocpHandler = ocpHandler;
      
      self.integratorFun = integrator.integratorFun;
      
      self.nlpVarsStruct = OclTree();
      self.nlpVarsStruct.addRepeated({'states','integratorVars','controls'},...
                                      {system.statesStruct,...
                                      integrator.varsStruct,...
                                      system.controlsStruct},self.N);
      self.nlpVarsStruct.add('states',system.statesStruct);
      
      self.nlpVarsStruct.add('parameters',self.system.parametersStruct);
      self.nlpVarsStruct.add('time',[1 1]);
      
      % initialize bounds      
      nlpVarsFlatFlat = self.nlpVarsStruct.getFlat;
      
      self.lowerBounds = Variable.create(nlpVarsFlatFlat,-inf);
      self.upperBounds = Variable.create(nlpVarsFlatFlat,inf);
      self.lowerBounds.time.set(0);
      
      self.scalingMin = Variable.create(nlpVarsFlatFlat,0);
      self.scalingMax = Variable.create(nlpVarsFlatFlat,1);
      
      nvars = (N+1)*self.nx + N*self.ni + N*self.nu;
      fh = @(self,varargin)self.getNLPFun(varargin{:});
      self.nlpFun = OclFunction(self,fh,{[nvars,1]},5);
    end    
  
    % public methods
    function s = getStructure(self)
      s = struct;
      s.states = cell(self.N+1,1);
      s.integratorVars = cell(self.N,1);
      s.controls = cell(self.N,1);
      for k:1:self.N
        s.states{k} = [self.nx,1];
        s.integratorVars{k} = [self.ni,1];
        s.controls{k} = [self.nu,1];
      end
      s.states{N+1} = [self.nx,1];
      s.parameters = [self.np,1];
      s.time = [1,1];
    end
    
    function [lb,ub] = getBounds(self)
      lb = self.lowerBounds.value;
      ub = self.upperBounds.value;
    end
    
    function [scalingMin,scalingMax] = getScaling(self)
      scalingMin = self.scalingMin;
      scalingMax = self.scalingMax;
    end
    
    function initialGuess = getInitialGuess(self)
      initialGuess = Variable.create(self.nlpVarsStruct,0);
      
      [lb,ub] = getBounds(self)
      
      guessValues = (lb + ub) / 2;
      
      % set to lowerBounds if upperBounds are inf
      indizes = isinf(ub);
      guessValues(indizes) = lb(indizes);
      
      % set to upperBounds of lowerBounds are inf
      indizes = isinf(lb);
      guessValues(indizes) = ub(indizes);
      
      % set to zero if both lower and upper bounds are inf
      indizes = isinf(lb) & isinf(ub);
      guessValues(indizes) = 0;

      initialGuess.set(guessValues);
    end
    
    function interpolateGuess(self,guess)
      for i=1:self.N
        state = guess.states(i).value;
        guess.integratorVars(i).states.set(state);
      end
    end
    
    function setParameter(self,id,varargin)
      % setParameter(id,lower,upper)
      % setParameter(id,value)     
      self.setBound(id,'all',varargin{:},false)
    end
    
    function setInitialBounds(self,id,varargin)
      % setInitialBound(id,lower,upper)
      % setInitialBound(id,value)     
      self.setBound(id,1,varargin{:},false)
    end
    
    function setEndBounds(self,id,varargin)
      % setEndBound(id,lower,upper)
      % setEndBound(id,value)     
      self.setBound(id,'end',varargin{:},false)
    end
    
    function setBounds(self,id,varargin)
      % setVariableBound(id,lower,upper)
      % setVariableBound(id,value)     
      self.setBound(id,'all',varargin{:})
    end
    
    function setBound(self,id,slice,varargin)
      % addBound(id,slice,lower,upper,showWarning=true)
      % addBound(id,slice,value,showWarning=true)
      
      if nargin == 4
        lower = varargin{1};
        upper = varargin{1};
        showWarning = true;
      elseif nargin == 5
        if islogical(varargin{2})
          lower = varargin{1};
          upper = varargin{1};
          showWarning = varargin{2};
        else
          lower = varargin{1};
          upper = varargin{2};
          showWarning = true;
        end
      elseif nargin == 6
          lower = varargin{1};
          upper = varargin{2};
          showWarning = varargin{3};
      end
      lowValNotInf = ~isinf(self.lowerBounds.get(id).get(slice).value);
      upValNotInf  = ~isinf(self.upperBounds.get(id).get(slice).value);
      if showWarning && (any(lowValNotInf(:)) || any(upValNotInf(:)))
        warning(['Existing bound overwritten. Make sure that setBounds ', ...
                 'is always called before setInitialBounds and setEndBounds']);
      end
      
      self.lowerBounds.get(id).get(slice).set(lower);
      self.upperBounds.get(id).get(slice).set(upper);
      
      self.scalingMin.get(id).get(slice).set(lower);
      self.scalingMax.get(id).get(slice).set(upper);
    end
    
    function setVariableScaling(self,id,varargin)
      % setVariableScaling(id,lower,upper)
      % setVariableScaling(id,value)     
      self.setScaling(id,'all',varargin{:})
    end
    
    function setScaling(self,id,slice,valMin,valMax)
      
      if valMin == valMax
        error('Can not scale with zero range for the variable');
      end
      self.scalingMin.get(id,slice).set(valMin);
      self.scalingMax.get(id,slice).set(valMax);     
    end
    
    function checkScaling(self)
      
      if any(isinf(self.scalingMin.value)) || any(isinf(self.scalingMax.value))
        error('Scaling information for some variable missing. Provide scaling for all variables or set scaling option to false.');
      end
      
    end
    
    function getCallback(self,var,values)
      self.ocpHandler.callbackFunction(var,values);
    end

    function [costs,constraints_Val,constraints_LB,constraints_UB,timeGrid] = getNLPFun(self,nlpVars)
      
      N = self.N;
      T = nlpVars.endTime;
      parameters = nlpVars.parameters;

      timeGrid = linspace(0,T,self.N+1);
      
      % N integrator equations
      % N path constraints
      % N continuity constraints
      % 1 boundary condition
      constraints = cell(3*N+1,1);
      constraints_LB = cell(3*N+1,1);
      constraints_UB = cell(3*N+1,1);
      
      costs = 0;
      thisStates = nlpVars.states{1};
      
      for k=1:N
        k_integratorEquations = 3*(k-1)+1
        k_pathConstraints = 3*(k-1)+2
        k_continuity = 3*(k-1)+2
        
        thisIntegratorVars = nlpVars.integratorVars{k};
        thisControls = nlpVars.controls{k};
        
        % add integrator equations
        [endStates, endAlgVars, integrationCosts, integratorEquations] = ...
              self.integratorFun.evaluate(thisStates,...
                                          thisIntegratorVars,...
                                          thisControls,...
                                          timeGrid(k),...
                                          timeGrid(k+1),...
                                          T,parameters);
        constraints{k_integratorEquations} = integratorEquations;
        constraints_LB{k_integratorEquations} = zeros*size(integratorEquations);
        constraints_UB{k_integratorEquations} = zeros*size(integratorEquations);
        
        costs = costs + integrationCosts;
        
        % go to next time gridpoint
        thisStates = nlpVars.states{k+1};
        
        % add path constraints
        [pathConstraint,lb,ub] = ...
              self.ocpHandler.pathConstraintsFun.evaluate(thisStates,... 
                                                          finalAlgVars,...
                                                          thisControls,...
                                                          timeGrid(k+1),...
                                                          parameters);                                   
        constraints{k_pathConstraints} = pathConstraint;
        constraints_LB{k_pathConstraints} = lb;
        constraints_UB{k_pathConstraints} = ub;
        
        % continuity equation
        continuity_constraint = thisStates - finalStates;
        constraints{k_continuity} = continuity_constraint;
        constraints_LB{k_continuity} = zeros*size(continuity_constraint);
        constraints_UB{k_continuity} = zeros*size(continuity_constraint);
      end
      
      % add terminal cost
      terminalCosts = self.ocpHandler.arrivalCostsFun.evaluate(thisStates,T,parameters);
      costs = costs + terminalCosts;

      % add boundary constraints
      [boundaryConditions,lb,ub] = self.ocpHandler.boundaryConditionsFun.evaluate(initialStates,thisStates,parameters);
      ineqConstraints{N+1} = boundaryConditions;
      ineqConstraints_LB{N+1} = lb;
      ineqConstraints{N+1} = ub;
      
      costs = costs + self.ocpHandler.getDiscreteCosts(nlpVars);    
      
      constraints_Val = [eqConstraints{:}];
      constraints_LB = [constraints_LB{:}];
      constraints_UB = [constraints_UB{:}];
    
    end % getNLPFun
  end % methods
end % classdef

