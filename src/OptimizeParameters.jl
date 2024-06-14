function get_parameter_upper_bound(tree)
    ranges = Dict('R'=>1.0e9,'C'=>10,'L'=>5,'P'=>[1.0e9,1],'W'=>1.0e9,'+'=>0,'-'=>0) 
    return [ranges[node.Type] for node in tree]
end

function get_parameter_upper_bound(readablecircuit::String) # C alternate upper bound: 0.01
    elements = foldl(replace,["["=>"","]"=>"","-"=>"",","=>""],init = denumber_circuit(readablecircuit))
    ranges = Dict('R'=>1.0e9,'C'=>10,'L'=>5,'P'=>[1.0e9,1],'W'=>1.0e9,'+'=>0,'-'=>0) 
    return flatten([ranges[e] for e in elements])
end

function get_parameter_upper_bound(readablecircuit::String, ranges::Dict{Char, Any})
    ranges['+'] = 0; ranges['-'] = 0;
    elements = foldl(replace,["["=>"","]"=>"","-"=>"",","=>""],init = denumber_circuit(readablecircuit))
    return flatten([ranges[e] for e in elements])
end

function func_and_params_for_optim(tree) 
    circuit,circuit_parameters,param_inds = tree_to_circuit_with_inds(tree)
    circuitfunc = circuitfunction(circuit)
    upperbounds = get_parameter_upper_bound(tree)[param_inds]
    return circuitfunc, flatten(circuit_parameters) , flatten(upperbounds) , param_inds
end

function func_and_params_for_optim(tree,bounds) 
    circuit,circuit_parameters,param_inds = tree_to_circuit_with_inds(tree)
    circuitfunc = circuitfunction(circuit)
    lowers, uppers = get_parameter_bounds(tree,bounds)
    return circuitfunc, flatten(circuit_parameters) , flatten(lowers[param_inds]),flatten(uppers[param_inds]) ,param_inds
end

function optimizeparameters(objective,initial_parameters,upper)
    lower = zeros(length(initial_parameters))
    inner_optimizer = NelderMead() 
    results = optimize(objective, lower, upper, initial_parameters, Fminbox(inner_optimizer), Optim.Options(time_limit = 20.0))
    return results.minimizer,results.minimum 
end

function optimizeparameters(objective,initial_parameters,lower,upper)
    inner_optimizer = NelderMead() 
    results = optimize(objective, lower, upper, initial_parameters, Fminbox(inner_optimizer), Optim.Options(time_limit = 20.0))
    return results.minimizer,results.minimum 
end

"""
    parameteroptimisation(circuitstring::String,measurements::Array{Complex{Float64},1},frequencies::Array{Float64,1},;x0=nothing,weights = nothing, fixed_params = nothing, optim_method = :de_rand_1_bin)
   
Fit the parameters of a given equivalent circuit to measurement values, using the Nelder-Mead simplex algorithm.

The inputs are the string representation of a circuit (e.g. "R1-[C2,R3]-P4"), an array of complex-valued impedance measurements and their corresponding frequencies.
The output is NamedTuple of the circuit's components with their corresponding parameter values. Five optional keyword arguments are:

- `x0`: An optional initial parameterset
- `weights`: A vector of equal length as the frequencies. This can be used to attatch more importance to specific areas within the frequency range.
- `fixed_params`: A tuple with the indices of the parameters that are to be fixed during the optimisation and the corresponding fixed parameter values.
- `param_ranges`: A Dictionary with the circuit components as keys the upperbounds of their respective parameter values as values.
- `optim_method`: An alternative optimisation method to be used for the initial optimisation step. Methods from BlackBoxOptim.jl are supported. 
# Example
```julia

julia> using EquivalentCircuits, Random

julia> Random.seed!(25);

julia> measurements = [5919.9 - 15.7, 5918.1 - 67.5im, 5887.1 - 285.7im, 5428.9 - 997.1im, 3871.8 - 978.9im, 
3442.9 - 315.4im, 3405.5 - 242.5im, 3249.6 - 742.0im, 1779.4 - 1698.9im,  208.2 - 777.6im, 65.9 - 392.5im];

julia> frequencies = [0.10, 0.43, 1.83, 7.85, 33.60, 143.84, 615.85,  2636.65, 11288.38, 48329.30, 100000.00];

julia> parameteroptimisation("R1-[C2,R3-[C4,R5]]",measurements,frequencies)
(R1 = 19.953805651358255, C2 = 3.999778355811269e-9, R3 = 3400.0089192843684, C4 = 3.999911415903211e-6, R5 = 2495.2493215522577)
"""
function parameteroptimisation(circuitstring::String,measurements,frequencies;x0=nothing,weights = nothing, fixed_params = nothing, param_ranges = nothing, optim_method = :de_rand_1_bin)
    elements = foldl(replace,["["=>"","]"=>"","-"=>"",","=>""],init = denumber_circuit(circuitstring))
    initial_parameters = flatten(karva_parameters(elements));
    if isnothing(fixed_params)
        circfunc = circuitfunction(circuitstring)
    else
        circfunc = circtuitfunction_fixed_params(circuitstring,fixed_params[1],fixed_params[2])
    end
    objective = objectivefunction(circfunc,measurements,frequencies,weights) 
    lower = zeros(length(initial_parameters))
    upper = isnothing(param_ranges) ? get_parameter_upper_bound(circuitstring) : get_parameter_upper_bound(circuitstring, param_ranges)

    ### First step ###
    SR = Array{Tuple{Float64,Float64},1}(undef,length(initial_parameters))
    for (e,(l,u)) in enumerate(zip(lower,upper))
        SR[e] = (l,u)
    end
    
    ### Add initial guess if provided ###
    if isnothing(x0)
        res = bboptimize(objective; SearchRange = SR, Method = optim_method,MaxSteps=70000,TraceMode = :silent);
        initial_parameters = best_candidate(res);
        fitness_1 = best_fitness(res);
         ### Second step ###
        inner_optimizer = NelderMead()
        results = optimize(objective, lower, upper, initial_parameters, Fminbox(inner_optimizer), Optim.Options(time_limit = 50.0)); #20.0
        fitness_2 = results.minimum
        best = results.minimizer
        parameters = fitness_2 < fitness_1 ? best : initial_parameters
    else
        res = bboptimize(objective, x0; SearchRange = SR, Method = optim_method,MaxSteps=70000,TraceMode = :silent);
        parameters =  best_candidate(res)
    end

    return parametertuple(circuitstring,parameters)
end
"""
    parameteroptimisation(circuitstring::String,filepath::String)

Fit the parameters of a given equivalent circuit to measurement values, using the Nelder-Mead simplex algorithm.

The inputs are the string representation of a circuit (e.g. "R1-[C2,R3]-P4") and a filepath to a CSV file containing the three following columns: 
the real part of the impedance, the imaginary part of the impedance, and the frequencies corresponding to the measurements.
The output is NamedTuple of the circuit's components with their corresponding parameter values.
"""
function parameteroptimisation(circuitstring::String,data::String;weights = nothing, fixed_params = nothing, param_ranges = nothing, optim_method = :de_rand_1_bin) 
    meansurement_file = readdlm(data,',')
    # convert the measurement data into usable format.
    reals = meansurement_file[:,1]
    imags = meansurement_file[:,2]
    frequencies = meansurement_file[:,3]
    measurements = reals + imags*im
#   generate initial parameters.
    elements = foldl(replace,["["=>"","]"=>"","-"=>"",","=>""],init = denumber_circuit(circuitstring))
    initial_parameters = flatten(karva_parameters(elements));
    if isnothing(fixed_params)
        circfunc = circuitfunction(circuitstring)
    else
        circfunc = circtuitfunction_fixed_params(circuitstring,fixed_params[1],fixed_params[2])
    end
    objective = objectivefunction(circfunc,measurements,frequencies,weights) 
    lower = zeros(length(initial_parameters))
    upper = isnothing(param_ranges) ? get_parameter_upper_bound(circuitstring) : get_parameter_upper_bound(circuitstring, param_ranges)
    ### First step ###
    SR = Array{Tuple{Float64,Float64},1}(undef,length(initial_parameters))
    for (e,(l,u)) in enumerate(zip(lower,upper))
        SR[e] = (l,u)
    end
    res = bboptimize(objective; SearchRange = SR, Method = optim_method,MaxSteps=170000,TraceMode = :silent); #70000
    initial_parameters = best_candidate(res)
    fitness_1 = best_fitness(res)
    ### Second step ###
    inner_optimizer = NelderMead()
    results = optimize(objective, lower, upper, initial_parameters, Fminbox(inner_optimizer), Optim.Options(time_limit = 50.0)); #20.0
    fitness_2 = results.minimum
    best = results.minimizer

    parameters = fitness_2 < fitness_1 ? best : initial_parameters

    return parametertuple(circuitstring,parameters)
end

function deflatten_parameters(parameters,tree,param_inds)
    correct_value_lengths = length.(get_tree_parameters(tree)[param_inds])
    correct_length = length(correct_value_lengths)
    deflattened_parameters = Array{Any}(undef,length(correct_value_lengths))
    flat_index_counter = 1
    for (e,v) in enumerate(correct_value_lengths)
        if v == 1
            deflattened_parameters[e] = parameters[flat_index_counter]
            flat_index_counter += 1
        else
            deflattened_parameters[e] = [parameters[flat_index_counter],parameters[flat_index_counter+1]]
            flat_index_counter += 2
        end
    end
    return deflattened_parameters
end

function deflatten_parameters(parameters,circuit)
    elements = foldl(replace,["["=>"","]"=>"","-"=>"",","=>""],init = denumber_circuit(circuit))
    correct_value_lengths = [e=='P' ? 2 : 1 for e in elements]
    correct_length = length(correct_value_lengths)
    deflattened_parameters = Array{Any}(undef,length(correct_value_lengths))
    flat_index_counter = 1
    for (e,v) in enumerate(correct_value_lengths)
        if v == 1
            deflattened_parameters[e] = parameters[flat_index_counter]
            flat_index_counter += 1
        else
            deflattened_parameters[e] = [parameters[flat_index_counter],parameters[flat_index_counter+1]]
            flat_index_counter += 2
        end
    end
    return deflattened_parameters
end