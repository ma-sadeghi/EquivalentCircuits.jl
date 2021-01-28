genfun(expr,args::Union{Vector,Tuple}) = eval(:(($(args...),)->$expr)) |> FunctionWrappers.FunctionWrapper{Any, Tuple{Array{Float64,1},Float64}}
genfun(expr,args::Symbol...) = genfun(expr,args) |> FunctionWrappers.FunctionWrapper{Any, Tuple{Array{Float64,1},Float64}}
genfun(expr,args::Union{Vector,Tuple}) = eval(:(($(args...),)->$expr)) |> FunctionWrappers.FunctionWrapper{Any, Tuple{Array{Any,1},Float64}}
genfun(expr,args::Symbol...) = genfun(expr,args) |> FunctionWrappers.FunctionWrapper{Any, Tuple{Array{Any,1},Float64}}

function circuitfunction(Circuit)
    for (f,t) in zip(["-","[",",","]"],["+","((",")^-1+(",")^-1)^-1"])
        Circuit=replace(Circuit,f=>t)
    end
    for I in 2:-1:1
        Es = eachmatch(Regex("([CLRP])([0-9]){$(I)}"),Circuit)
            for e in Es
                match = e.match
                if match[1] == 'C'
                 Circuit = replace(Circuit,match=>"(1/(2im*π*f*"*"T"*"))")
                elseif match[1] == 'R'
                 Circuit = replace(Circuit,match=>"T")
                elseif match[1] == 'L'
                 Circuit = replace(Circuit,match=>"(2im*π*f*"*"T"*")")
             elseif match[1] == 'P'
                 Circuit = replace(Circuit,match=>"T*(2*π*f)^(-N)"*"*(cos((π*N)*0.5)-sin((π*T)*0.5)im)")
            end
        end
end
new_circuit = ""
counter = 1
for i in Circuit
    if i == 'T'
        new_circuit = new_circuit*"T["*string(counter)*"]"
        counter += 1
    elseif i == 'N'
        new_circuit = new_circuit*"T["*string(counter)*"]"
    else
        new_circuit = new_circuit*i
    end
end

    Circuit_expression = Meta.parse(new_circuit)
    return genfun(Circuit_expression,[:T,:f])
end

function tree_to_function(tree_array)
    dictionary_of_calculations = Dict('R'=>"T",'C'=>"(1/(2im*π*f*"*"T"*"))",'L'=>"(2im*π*f*"*"T"*")",'P'=>"T[1]*(2*π*f)^(-T[2])"*"*(cos((π*T[2])*0.5)-sin((π*T[2])*0.5)im)") 
    tree = copy(tree_array) 
    nodecount = length(tree)
    essential_info = [[node.ParentIndex,node.Type,node.Index] for node in tree]
    for i in 1:((length(essential_info)-1)/2)
        parent1,type1,index1 = pop!(essential_info)
        parent2,type2,index2 = pop!(essential_info)
        type1 = haskey(dictionary_of_calculations,type1) ? replace(dictionary_of_calculations[type1],"T"=>"T["*string(index1)*']') : type1
        type2 = haskey(dictionary_of_calculations,type2) ? replace(dictionary_of_calculations[type2],"T"=>"T["*string(index2)*']') : type2
        operation = essential_info[parent1][2]
        if operation == '+'
            essential_info[parent1][2] = type1*'+'*type2
        elseif operation == '-'
            essential_info[parent1][2] = "((("*type1*")^-1)+("*type2*")^-1)^-1"
        end
    end
    CircuitExpression = Meta.parse(essential_info[1][2])
return genfun(CircuitExpression,[:T,:f])
end

karva_to_function(karva) = tree_to_function(karva_to_tree(karva))

function flatten(params)
    new_array = Float64[]
    for param in params
        if length(param) == 1
            push!(new_array,param)
        else
            push!(new_array,param[1])
            push!(new_array,param[2])
        end
    end
    return new_array
end

function get_target_impedance(circuit,circuit_parameters,frequency=1000)
    circfunc = circuitfunction(circuit)
    target_impedance = circfunc(flatten(circuit_parameters),frequency)
   return target_impedance
end