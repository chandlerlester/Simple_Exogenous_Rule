#==============================================================================
    Code for solving the Hamiltonian Jacboi Bellman for
	   an Ramsey Model with a diffusion process for capital

       This version of the code updates the grid for capital
        along with estimates for the unknown parameter

	Algorithm code from Matlab code by Ben Moll:
        http://www.princeton.edu/~moll/HACTproject.htm

        Updated to julia 1.0.0
==============================================================================#

using Distributions, Plots, LinearAlgebra, SparseArrays

γ= 2.0 #gamma parameter for CRRA utility
ρ = 0.05 #the discount rate
α = 1/3 # the curvature of the production function (cobb-douglas)
δ = 0.05 # the depreciation rate
σ = .5 #variance term
n = .51 #growth of labor


#=============================================================================
 	k our capital follows a process that depends on
            dk = (s⋅f(k) - (δ-σ^2)k)dt - σ⋅k⋅dW_[t]
        Where W is a Wiener process
=============================================================================#
#K_starting point, for mean of z process
k_st = ((α)/(ρ+δ+n-σ^2))^(1/(1-α))
println(k_st)
# create the grid for k
H= 1000 #number of points on grid
k_min_1 = .1*k_st # min value
k_max_1 = 10 .*k_st # max value
k = LinRange(k_min_1, k_max_1, H)
k_1=k
dk = (k_max_1-k_min_1)/(H-1)

#create matrices for k and z
kk = k*1.

# use Ito's lemma to find the drift and variance of our optimization equation

max_it = 100
ε = 0.1^(6)
Δ = 1000

# set up all of these empty matrices
Vaf_1, Vab_1, c_1 = [zeros(H,1) for i in 1:3]

y = pdf.(Normal(.99, σ), k)
plot(k,y, grid=false,
		xlabel="k", ylabel="Probability",
		legend=false, color="purple", title="PDF of k")
png("PDF of k")

#============================================================================#
# Now it's time to solve the model, first put in a guess for the value function
v0 = (kk.^α).^(1-γ)/(1-γ)/ρ
v_1=v0

maxit= 30 #set number of iterations (only need 6 to converge)
dist = [] # set up empty array for the convergence criteria

for j = 1:maxit
    V=v_1

    #Now set up the forward difference

    Vaf_1[1:H-1,:] = (V[2:H, :] - V[1:H-1,:])/dk
    Vaf_1[H,:] .= (k_max_1.^α - (δ+n-σ^2).*k_max_1).^(-γ) # imposes a constraint

    #backward difference
    Vab_1[2:H,:] = (V[2:H, :] - V[1:H-1,:])/dk
    Vab_1[1,:] .= (k_min_1.^α - (δ+n-σ^2).*k_min_1).^(-γ)

    #I_concave = Vab .> Vaf # indicator for whether the value function is concave

    # Consumption and savings functions
    cf = Vaf_1.^(-1/γ)
    drf =(1 .-(cf/kk.^α))*kk.^α-(δ+n-σ^2).*kk

    # consumption and saving backwards difference
    cb = Vab_1.^(-1.0/γ)
    drb = (1 .-(cb/k.^α))*kk.^α.-(δ+n-σ^2).*kk
    #println(sb)
    #consumption and derivative of the value function at the steady state

    c0 = kk.^α - (δ+n-σ^2).*kk
    Va0 = c0.^(-γ)

    # df chooses between the forward or backward difference

    If = drf.>0 # positive drift will ⇒ forward difference
    Ib = drb.<0 # negative drift ⇒ backward difference
    I0=(1.0.-If-Ib) # at steady state

    Va_upwind = Vaf_1.*If + Vab_1.*Ib + Va0.*I0 # need to include SS term

    global c_1 = Va_upwind.^(-1/γ)
    u = (c_1.^(1-γ))/(1-γ)

    # Now to constuct the A matrix
    X = -min.(drb, 0)/dk + (σ.*kk/(2*dk))
    Y = -max.(drf, 0)/dk + min.(drb, 0)/dk - (σ.*kk/(dk))
    Z = max.(drf, 0)/dk + (σ.*kk/(2*dk))

    updiag = 0
    updiag =[updiag; Z[1:H-1,1]; 0]
    updiag =(updiag[:])

    centerdiag=reshape(Y, H, 1)
    centerdiag = (centerdiag[:]) # for tuples

   lowdiag = X[2:H, 1]
   lowdiag=(lowdiag)

   # spdiags in Matlab allows for automatic trimming/adding of zeros
       # spdiagm does not do this
  A = sparse(Diagonal(centerdiag))+ [zeros(1, H); sparse(Diagonal(lowdiag)) zeros(H-1,1)] + sparse(Diagonal(updiag))[2:end, 1:H] # trim first element

  B = (1/Δ + ρ)*sparse(I,H,H) - A

  u_stacked= reshape(u, H, 1)
  V_stacked = reshape(V,H, 1)

  b = u_stacked + (V_stacked./Δ)

  V_stacked = B\b

  V = reshape(V_stacked, H, 1)

  V_change = V-v_1

  global v_1= V
  # need push function to add to an already existing array
  push!(dist, findmax(abs.(V_change))[1])
  if dist[j].< ε
      println("Value Function Converged Iteration=")
      println(j)
      break
  end

end

# calculate the savings for kk
ss_1 = kk.^α - (δ+n-σ^2).*kk

# Plot the savings vs. k
plot(k, c_1, grid=false,
		xlabel="k", ylabel="s(k)",
        xlims=(k_min_1,k_max_1),
		legend=false, title="Optimal Consumption Policies")
plot!(k, zeros(H,1), line=:dash, color=:black)
png("OptimalCons")


plot(k, ss_1, grid=false,
		xlabel="k", ylabel="s(k)",
        xlims=(k_min_1,k_max_1),
		legend=false, title="Optimal Savings Policies")
plot!(k, zeros(H,1), line=:dash, color=:black)
png("OptimalSavings")


# Plot the interest rate
r_1 = α.*kk.^(α-1)
plot(k, r_1, grid=false,
		xlabel="k", ylabel="r(k)",
        xlims=(k_min_1,k_max_1),
		legend=false, title="Optimal Interest Rate")
png("OptimalInterest")

plot(k, v_1, grid=false,
		xlabel="k", ylabel="V(k)",
		xlims=(k_min_1,k_max_1),
		legend=false, title="")
png("Value_function_vs_k")

#==================== Now resolve the model with σ misspecified =======#

# create a random distribution to pull from
Dist = Bernoulli(.45)
T = 10000# set the number of external time periods to 10,000

# Add in the misspecification
σ_g =.02 #original is that σ =.5
Σ_g=[σ_g]
# set up all of these empty matrices
Vaf_2, Vab_2, c_2 = [zeros(H,1) for i in 1:3]
Val_2 =[]
savings=[]
grid=[]
cons=[]

maxit= 30 #set number of iterations for d
for t in 1:T
    # Now it's time to solve the model, first put in a guess for the value function
    k_st_2 = ((α)/(ρ+δ+n-σ_g^2))^(1/(1-α))

    k_min = .1*k_st_2 # min value
    k_max = 10 .*k_st_2 # max value
    global k = LinRange(k_min, k_max, H)
    global dk = (k_max-k_min)/(H-1)
    global kk = k*1.
    push!(grid,k)

    global v0 = (kk.^α).^(1-γ)/(1-γ)/ρ
    v_2=v0
    global dist = [] # needs to be in the time loop to work properly
    indicator = rand(Dist)
    for j = 1:maxit
        V=v_2

        #Now set up the forward difference

        Vaf_2[1:H-1,:] = (V[2:H, :] - V[1:H-1,:])/dk
        Vaf_2[H,:] .= (k_max.^α - (δ+n-σ_g^2).*k_max).^(-γ) # imposes a constraint

        #backward difference
        Vab_2[2:H,:] = (V[2:H, :] - V[1:H-1,:])/dk
        Vab_2[1,:] .= (k_min.^α - (δ+n-σ_g^2).*k_min).^(-γ)

        #I_concave = Vab .> Vaf # indicator for whether the value function is concave

        # Consumption and savings functions
        cf = Vaf_2.^(-1/γ)
        drf =(1 .-(cf/kk.^α))*kk.^α-(δ+n-σ_g^2).*kk

        # consumption and saving backwards difference
        cb = Vab_2.^(-1.0/γ)
        drb = (1 .-(cb/k.^α))*kk.^α-(δ+n-σ_g^2).*kk

        #consumption and derivative of the value function at the steady state

        c0 = kk.^α - (δ+n-σ_g^2).*kk
        Va0 = c0.^(-γ)

        # df chooses between the forward or backward difference

        If = drf.>0 # positive drift will ⇒ forward difference
        Ib = drb.<0 # negative drift ⇒ backward difference
        I0=(1.0.-If-Ib) # at steady state

        Va_upwind = Vaf_2.*If + Vab_2.*Ib + Va0.*I0 # need to include SS term

        global c_2 = Va_upwind.^(-1/γ)
        u = (c_2.^(1-γ))/(1-γ)

        # Now to constuct the A matrix
        X = -min.(drb, 0)/dk + (σ_g.*kk/(2*dk))
        Y = -max.(drf, 0)/dk + min.(drb, 0)/dk - (σ_g.*kk/(dk))
        Z = max.(drf, 0)/dk + (σ_g.*kk/(2*dk))

        updiag = 0
        updiag =[updiag; Z[1:H-1,1]; 0]
        updiag =(updiag[:])

        centerdiag=reshape(Y, H, 1)
        centerdiag = (centerdiag[:]) # for tuples

       lowdiag = X[2:H, 1]
       lowdiag=(lowdiag)

       # spdiags in Matlab allows for automatic trimming/adding of zeros
           # spdiagm does not do this
      A = sparse(Diagonal(centerdiag))+ [zeros(1, H); sparse(Diagonal(lowdiag)) zeros(H-1,1)] + sparse(Diagonal(updiag))[2:end, 1:H] # trim first element

      B = (1/Δ + ρ)*sparse(I,H,H) - A

      u_stacked= reshape(u, H, 1)
      V_stacked = reshape(V,H, 1)

      b = u_stacked + (V_stacked./Δ)

      V_stacked = B\b

      V = reshape(V_stacked, H, 1)

      V_change = V-v_2

      v_2= V
      # need push function to add to an already existing array
      push!(dist, findmax(abs.(V_change))[1])
      if dist[j].< ε
        push!(Val_2, v_2)
        break
      end
    end
    push!(Σ_g, σ_g)
    # calculate the savings for kk
    ss_2 = kk.^α - (δ+n-σ_g^2).*kk
    push!(savings, ss_2)
    push!(cons,c_2)
    # add in updating
    if indicator ==1
        global σ_g = σ_g + .001(σ-σ_g)
    end
    println(t)
end


# Plot the savings vs. k
plot(k[1:H-1], c_2[1:H-1], grid=false,
		xlabel="k", ylabel="c(k)",
        xlims=(k[1],k[end]),legend=:bottomright,
		label="Guess", title="Optimal Consumption Policies")
plot!(k[1:H-1],c_1[1:H-1], label="Actual", line=:dash)
png("OptimalCons")

plot(k[1:H-1],cons[end][1:H-1], grid=false,
		xlabel="k", ylabel="c(k)",
        xlims=(k[1],k[end]),label="10,000th period", legend=:bottomright,
        title="Optimal Consumption Policies", color=:hotpink)
plot!(k[1:H-1],cons[500][1:H-1], label="500th period", color=:blue)
plot!(k[1:H-1],cons[1][1:H-1], label="Initial", color=:green)
plot!(k[1:H-1],c_1[1:H-1], label="Actual", line=:dot, color=:black)
png("OptimalCons_2")

plot(grid[end][1:H-1], c_2[1:H-1], grid=false,
		xlabel="k", ylabel="c(k)",
        xlims=(k[1],k[end]), legend=:bottomright,
		label="t=10,000", title="Optimal Consumption Policies", line=:dash)
plot!(grid[5000][1:H-1],cons[5000][1:H-1], label="t=5,000", line=:dash)
plot!(grid[1][1:H-1],cons[1][1:H-1], label="t=1", line=:dash)
plot!(k_1[1:H-1],c_1[1:H-1], label="Actual")
png("OptimalCons_adjusted")

plot(k, savings[end], grid=false,
		xlabel="k", ylabel="s(k)",
        xlims=(k[1],k[end]),label="10,000th period",
        title="Optimal Savings Policies", color=:hotpink)
plot!(k, zeros(H,1), color=:black, label="")
plot!(k,savings[500], label="500th period", color=:blue)
plot!(k,savings[1], label="Initial", color=:green)
plot!(k,ss_1, label="Actual", line=:dot, color=:black)
png("OptimalSavings_2")

plot(grid[end], savings[end], grid=false,
		xlabel="k", ylabel="s(k)",
        xlims=(k[1],k[end]),label="10,000th period",
        title="Optimal Savings Policies", color=:hotpink,
        legend=:bottomleft)
plot!(grid[500],savings[500], label="500th period", color=:blue)
plot!(grid[1],savings[1], label="Initial", color=:green)
plot!(k_1,ss_1, label="Actual", line=:dot, color=:black)
plot!(k, zeros(H,1), line=:dash, color=:black, label="", legend=:bottomleft)
png("OptimalSavings_adjusted")


plot(k, savings[end], grid=false,
		xlabel="k", ylabel="s(k)",
        xlims=(k[1],k[end]),label="", title="Optimal Savings Policies")
plot!(k, zeros(H,1), line=:dash, color=:black, label="", legend=:bottomleft)
plot!(k,ss_1, label="Actual")
png("OptimalSavings_All")


plot(k_1, v_1, grid=false,
		xlabel="k", ylabel="V(k)",
		xlims=(k[1],k[end]), title="Value Functions",
        legend=:bottomright, color=:black, line=:dash,
        label="True")
plot!(grid[1],Val_2[1], label="Initial", color=:black)
plot!(grid[100],Val_2[100], label="guess, t=100", color=:green,)
plot!(grid[2000],Val_2[2000], label="guess, t=2,000", color=:orange)
plot!(grid[5000],Val_2[5000], label="guess, t=5,000", color=:red)
plot!(grid[1000],Val_2[1000], label="guess, t=1,000", color=:pink)
plot!(grid[end],Val_2[end], label="guess, t=10,000")
png("Value_function_vs_k_adjusted")

plot(k, v_1, grid=false,
		xlabel="k", ylabel="V(k)",
		xlims=(k[1],k[end]), title="Value Functions",
        legend=:bottomright, color=:black, line=:dash,
        label="True")
plot!(k,Val_2[1], label="Initial", color=:black)
plot!(k,Val_2[100], label="guess, t=100", color=:green,)
plot!(k,Val_2[2000], label="guess, t=2000", color=:orange)
plot!(k,Val_2[5000], label="guess, t=5000", color=:red)
plot!(k,Val_2[1000], label="guess, t=100", color=:pink)
plot!(k,Val_2[end], label="guess, t=10000", color=:hotpink)
png("Value_function_vs_k_2")


plot(k, Val_2, grid=false,
		xlabel="k", ylabel="V(k)",
		xlims=(k[1],k[end]), title="Value Functions", legend=false)
plot!(k,v_1, label="", color=:black, line=:dot)
png("Value_function_vs_k_all")


plot(grid, Val_2, grid=false,
		xlabel="k", ylabel="V(k)",
		xlims=(k[1],k[end]), title="Value Functions", legend=false)
plot!(k_1,v_1, label="", color=:black, line=:dot)
png("Value_function_vs_k_all_adjusted")

plot([1:T], Σ_g[2:end], grid=false,
		xlabel="t", ylabel="sigma_g", title="Guess Over time", legend=false)
plot!([1:T],ones(T).*σ, label="", color=:black)
png("sigma")
