CONTROL_INTERVALS = 40;     % control discretization

% Get and set solver options
options = OclOptions();
options.nlp.controlIntervals = CONTROL_INTERVALS;
options.nlp.collocationOrder = 3;
options.nlp.ipopt.linear_solver = 'mumps';
options.nlp.solver = 'ipopt';

ocl = OclSolver(CartPoleSystem,CartPoleOCP,options);

p0 = 0; v0 = 0;
theta0 = 180*pi/180; omega0 = 0;

ocl.setInitialBounds('p', p0);
ocl.setInitialBounds('v', v0); 
ocl.setInitialBounds('theta', theta0); 
ocl.setInitialBounds('omega', omega0); 

ocl.setEndBounds('p', 0);
ocl.setEndBounds('v', 0); 
ocl.setEndBounds('theta', 0); 
ocl.setEndBounds('omega', 0); 

ocl.setParameter('time', 0, 20);

% Get and set initial guess
initialGuess = ocl.getInitialGuess();

% Run solver to obtain solution
[sol,times] = ocl.solve(initialGuess);

% plot solution
handles = {};
pmax = max(abs(sol.states.p.value));
for k=2:length(times.states.value)
  t = times.states(k);
  x = sol.states(:,:,k);
  handles = visualizeCartPole(t, x, [0,0,0,0], -pmax, pmax, handles);
  dt = times.states(k)-times.states(k-1);
  pause(dt.value);
end
