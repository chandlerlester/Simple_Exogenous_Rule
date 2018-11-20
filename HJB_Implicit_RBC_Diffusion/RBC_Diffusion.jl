#==============================================================================
    Code for solving the Hamiltonian Jacboi Bellman for
	   an RBC model with a Diffusion process

	Translated Julia code from Matlab code by Ben Moll:
        http://www.princeton.edu/~moll/HACTproject.htm
==============================================================================#

using Parameters, Distributions, Plots

@with_kw type RBC_Model_parameters
    γ= 2.0 #gamma parameter for CRRA utility
    ρ = 0.05 #the discount rate
    α = 0.3 # the curvature of the production function (cobb-douglas)
    δ = 0.05 # the depreciation rate
end


# Z our state variable follows this process
@with_kw type Ornstein_Uhlenbeck_parameters
	#= for this process:
	 		dlog(z) = -θ⋅log(z)dt + σ^2⋅dw
		and
			log(z)∼N(0,var) where var = σ^2/(2⋅θ) =#
    var = 0.07
	μ_z = exp(var/2)
	corr = 0.9
	θ = -log(corr)
	σ_sq = 2*θ*var

end

RBC_param = RBC_Model_parameters()
OU_param = Ornstein_Uhlenbeck_parameters()

@unpack_RBC_Model_parameters(RBC_param)
@unpack_Ornstein_Uhlenbeck_parameters(OU_param)

#=============================================================================
 	k our capital follows a process that depends on z,

	using the regular formula for capital accumulation
	we would have:
		(1+ρ)k_{t+1} = k_{t}⋅f'(k_{t}) + (1-δ)k_{t}
	where:
		f(k_{t}) = z⋅k^{α} so f'(k_{t}) = (α)⋅z⋅k^{α-1}
	so in steady state where k_{t+1} = k_{t}
		(1+ρ)k = α⋅z⋅k^{α} + (1-δ)k
		k = [(α⋅z)/(ρ+δ)]^{1/(1-α)}

=============================================================================#
#K_starting point, for mean of z process

k_st = ((α⋅μ_z)/(ρ+δ))^(1/(1-α))

# create the grid for k
I = 15 #number of points on grid
k_min = 0.3*k_st # min value
k_max = 3*k_st # max value
k = linspace(k_min, k_max, I)
dk = (k_max-k_min)/(I-1)

# create the grid for z
J = 40
z_min = μ_z*0.8
z_max = μ_z*1.2
z = linspace(z_min, z_max, J)
dz = (z_max-z_min)/(J-1)
dz_sq = dz^2


# Check the pdf to make sure our grid isn't cutting off the tails of
	# our distribution
y = pdf.(LogNormal(0, var), z)
plot(z,y, grid=false,
		xlabel="z", ylabel="Probability",
		legend=false, color="purple", title="PDF of z")
png("PDF of z")

#create matrices for k and z
z= convert(Array, z)'
kk = k*ones(1,J)
zz = ones(I,1)*z

# use Ito's lemma to find the drift and variance of our optimization equation

μ = (-θ*log(z)+σ_sq/2).*z # the drift from Ito's lemma
Σ_sq = σ_sq.*z.^2 #the variance from Ito's lemma

max_it = 100
ε = 0.1^(6)
Δ = 1000

# set up all of these empty matrices
Vaf, Vab, Vzf, Vzb, Vzz, c = [zeros(I,J) for i in 1:6]

#==============================================================================

    Now we are going to construct a matrix summarizing the evolution of V_z

    This comes from the following discretized Bellman equation:

    ρv_ij = u(c_ij) + v_k(zF(k_{i}) -δk-c) + v_z⋅μ(z)
                                   + 1/2(v_{zz})σ^2(z)

                                   or

    ρv_ij = u(c_ij) + v_k(zF(k_{i}) -δk-c) + ((v_{i,j+1}-v_{i,j})/Δz)μ(z)
                            + 1/2((v_{i,j+1}-2v_{i,j}+v_{ij-1})/Δz^2)σ^2(z)

    Assume forward difference because of boundary conditions

==============================================================================#

 yy = (-Σ_sq/dz_sq - μ/dz)
 χ = Σ_sq/(2*dz_sq)
 ζ = μ/dz + Σ_sq/(2*dz_sq)


 # Define the diagonals of this matrix
 updiag = zeros(I,1)
 	for j = 1:J
		updiag =[updiag; repmat([ζ[j]], I, 1)]
	end
 updiag =(updiag[:])


 centerdiag=repmat([χ[1]+yy[1]],I,1)
	for j = 2:J-1
		centerdiag = [centerdiag; repmat([yy[j]], I, 1)]
	end
 centerdiag=[centerdiag; repmat([yy[J]+ζ[J]], I, 1)]
 centerdiag = centerdiag[:]

lowdiag = repmat([χ[2]], I, 1)
	for j=3:J
		lowdiag = [lowdiag; repmat([χ[j]],I,1)]
	end
lowdiag=lowdiag[:]

# spdiags in Matlab allows for automatic trimming/adding of zeros
    # spdiagm does not do this

B_switch = spdiagm(centerdiag)+ [zeros(I,I*J);  spdiagm(lowdiag) zeros(I*(J-1), I)]+ spdiagm(updiag)[(I+1):end,1:(I*J)] # trim off rows of zeros


# Now it's time to solve the model, first put in a guess for the value function
v0 = (zz.*kk.^α).^(1-γ)/(1-γ)/ρ
v=v0

maxit= 30 #set number of iterations (only need 6 to converge)
dist = [] # set up empty array for the convergence criteria

for n = 1:maxit
    V=v

    #Now set up the forward difference

    Vaf[1:I-1,:] = (V[2:I, :] - V[1:I-1,:])/dk
    Vaf[I,:] = (z.*k_max.^α - δ.*k_max).^(-γ) # imposes a constraint

    #backward difference
    Vab[2:I,:] = (V[2:I, :] - V[1:I-1,:])/dk
    Vab[1,:] = (z.*k_min.^α - δ.*k_min).^(-γ)

    #I_concave = Vab .> Vaf # indicator for whether the value function is concave

    # Consumption and savings functions
    cf = Vaf.^(-1/γ)
    sf = zz .* kk.^α - δ.*kk - cf

    # consumption and saving backwards difference

    cb = Vab.^(-1.0/γ)
    sb = zz .* kk.^α - δ.*kk - cb
    #println(sb)
    #consumption and derivative of the value function at the steady state

    c0 = zz.*kk.^α - δ.*kk
    Va0 = c0.^(-γ)

    # df chooses between the forward or backward difference

    If = sf.>0 # positive drift will ⇒ forward difference
    Ib = sb.<0 # negative drift ⇒ backward difference
    I0=(1-If-Ib) # at steady state

    Va_upwind = Vaf.*If + Vab.*Ib + Va0.*I0 # need to include SS term

    c = Va_upwind.^(-1/γ)
    u = (c.^(1-γ))/(1-γ)

    # Now to constuct the A matrix
    X = -min(sb, 0)/dk
    #println(X)
    Y = -max(sf, 0)/dk + min(sb, 0)/dk
    Z = max(sf, 0)/dk

    updiag = 0
       for j = 1:J
           updiag =[updiag; Z[1:I-1,j]; 0]
       end
    updiag =(updiag[:])

    centerdiag=reshape(Y, I*J, 1)
    centerdiag = (centerdiag[:]) # for tuples

   lowdiag = X[2:I, 1]
       for j = 2:J
           lowdiag = [lowdiag; 0; X[2:I,j]]
       end
   lowdiag=(lowdiag)

   # spdiags in Matlab allows for automatic trimming/adding of zeros
       # spdiagm does not do this
  AA = spdiagm(centerdiag)+ [zeros(1, I*J); spdiagm(lowdiag) zeros(I*J-1,1)] + spdiagm(updiag)[2:end, 1:(I*J)] # trim first element

  A = AA + B_switch
  B = (1/Δ + ρ)*speye(I*J) - A

  u_stacked= reshape(u, I*J, 1)
  V_stacked = reshape(V,I*J, 1)

  b = u_stacked + (V_stacked./Δ)

  V_stacked = B\b

  V = reshape(V_stacked, I, J)

  V_change = V-v

  v= V

  # need push function to add to an already existing array
  push!(dist, findmax(abs(V_change))[1])
  if dist[n].< ε
      println("Value Function Converged Iteration=")
      println(n)
      break
  end

end

# calculate the savings for kk
ss = zz.*kk.^α - δ.*kk - c

# Plot the savings vs. k
plot(k, ss, grid=false,
		xlabel="k", ylabel="s(k,z)",
        xlims=(k_min,k_max),
		legend=false, title="Optimal Savings Policies")
plot!(k, zeros(I,1))

png("OptimalSavings")

plot(k, v, grid=false,
		xlabel="k", ylabel="V(k)",
		xlims=(k_min,k_max),
		legend=false, title="")
png("Value_function_vs_k")

z = linspace(z_min, z_max, J)
plot(z, v', grid=false,
		xlabel="z", ylabel="V(z)",
		xlims=(z_min,z_max),
		legend=false, title="")
png("Value_function_vs_z")

z= convert(Array, z)'


#===========================================================================#


#  Now the agents misspecify θ and σ^2
θ_g = -8
σ_sq_g = .09

# They will update this based on a draw from a binomial

Dist = Bernoulli(.25)

μ_g = (-θ_g*log(z)+σ_sq_g/2).*z # the drift from Ito's lemma
Σ_sq_g = σ_sq_g.*z.^2 #the variance from Ito's lemma

max_it = 100
ε = 0.1^(6)
Δ = 1000

# set up all of these empty matrices
Vaf, Vab, Vzf, Vzb, Vzz, c = [zeros(I,J) for i in 1:6]

#==============================================================================

    Now we are going to construct a matrix summarizing the evolution of V_z

==============================================================================#

 yy_g = (-Σ_sq_g/dz_sq - μ_g/dz)
 χ_g = Σ_sq_g/(2*dz_sq)
 ζ_g = μ_g/dz + Σ_sq_g/(2*dz_sq)


 # Define the diagonals of this matrix
 updiag_g = zeros(I,1)
 	for j = 1:J
		updiag_g =[updiag_g; repmat([ζ_g[j]], I, 1)]
	end
 updiag_g =(updiag_g[:])


 centerdiag_g=repmat([χ_g[1]+yy_g[1]],I,1)
	for j = 2:J-1
		centerdiag_g = [centerdiag_g; repmat([yy_g[j]], I, 1)]
	end
 centerdiag_g=[centerdiag_g; repmat([yy_g[J]+ζ_g[J]], I, 1)]
 centerdiag_g = centerdiag_g[:]

lowdiag_g = repmat([χ_g[2]], I, 1)
	for j=3:J
		lowdiag_g = [lowdiag_g; repmat([χ_g[j]],I,1)]
	end
lowdiag_g=lowdiag_g[:]

# spdiags in Matlab allows for automatic trimming/adding of zeros
    # spdiagm does not do this

B_switch_g = spdiagm(centerdiag_g)+ [zeros(I,I*J);  spdiagm(lowdiag_g) zeros(I*(J-1), I)]+ spdiagm(updiag_g)[(I+1):end,1:(I*J)] # trim off rows of zeros


# Now it's time to solve the model, first put in a guess for the value function
v0 = (zz.*kk.^α).^(1-γ)/(1-γ)/ρ
v=v0

maxit= 30 #set number of iterations (only need 6 to converge)
dist = [] # set up empty array for the convergence criteria

for n = 1:maxit
    V=v

    #Now set up the forward difference

    indicator = rand(Dist)

    Vaf[1:I-1,:] = (V[2:I, :] - V[1:I-1,:])/dk
    Vaf[I,:] = (z.*k_max.^α - δ.*k_max).^(-γ) # imposes a constraint

    #backward difference
    Vab[2:I,:] = (V[2:I, :] - V[1:I-1,:])/dk
    Vab[1,:] = (z.*k_min.^α - δ.*k_min).^(-γ)

    #I_concave = Vab .> Vaf # indicator for whether the value function is concave

    # Consumption and savings functions
    cf = Vaf.^(-1/γ)
    sf = zz .* kk.^α - δ.*kk - cf

    # consumption and saving backwards difference

    cb = Vab.^(-1.0/γ)
    sb = zz .* kk.^α - δ.*kk - cb
    #println(sb)
    #consumption and derivative of the value function at the steady state

    c0 = zz.*kk.^α - δ.*kk
    Va0 = c0.^(-γ)

    # df chooses between the forward or backward difference

    If = sf.>0 # positive drift will ⇒ forward difference
    Ib = sb.<0 # negative drift ⇒ backward difference
    I0=(1-If-Ib) # at steady state

    Va_upwind = Vaf.*If + Vab.*Ib + Va0.*I0 # need to include SS term

    c = Va_upwind.^(-1/γ)
    u = (c.^(1-γ))/(1-γ)

    # Now to constuct the A matrix
    X = -min(sb, 0)/dk
    #println(X)
    Y = -max(sf, 0)/dk + min(sb, 0)/dk
    Z = max(sf, 0)/dk

    updiag = 0
       for j = 1:J
           updiag =[updiag; Z[1:I-1,j]; 0]
       end
    updiag =(updiag[:])

    centerdiag=reshape(Y, I*J, 1)
    centerdiag = (centerdiag[:]) # for tuples

   lowdiag = X[2:I, 1]
       for j = 2:J
           lowdiag = [lowdiag; 0; X[2:I,j]]
       end
   lowdiag=(lowdiag)

   # spdiags in Matlab allows for automatic trimming/adding of zeros
       # spdiagm does not do this
  AA = spdiagm(centerdiag)+ [zeros(1, I*J); spdiagm(lowdiag) zeros(I*J-1,1)] + spdiagm(updiag)[2:end, 1:(I*J)] # trim first element

  if indicator == 1
      B_switch_g = B_switch_g + .1(B_switch - B_switch_g)
  end

  A = AA + B_switch_g
  B = (1/Δ + ρ)*speye(I*J) - A

  u_stacked= reshape(u, I*J, 1)
  V_stacked = reshape(V,I*J, 1)

  b = u_stacked + (V_stacked./Δ)

  V_stacked = B\b

  V = reshape(V_stacked, I, J)

  V_change = V-v

  v= V

  # need push function to add to an already existing array
  push!(dist, findmax(abs(V_change))[1])
  if dist[n].< ε
      println("Value Function Converged Iteration=")
      println(n)
      break
  end

end

# calculate the savings for kk
ss = zz.*kk.^α - δ.*kk - c

# Plot the savings vs. k
plot(k, ss, grid=false,
		xlabel="k", ylabel="s(k,z)",
        xlims=(k_min,k_max),
		legend=false, title="Optimal Savings Policies")
plot!(k, zeros(I,1))
png("OptimalSavings_2")

plot(k, v, grid=false,
		xlabel="k", ylabel="V(k)",
		xlims=(k_min,k_max),
		legend=false, title="")
png("Value_function_vs_k_2")

z = linspace(z_min, z_max, J)
plot(z, v', grid=false,
		xlabel="z", ylabel="V(z)",
		xlims=(z_min,z_max),
		legend=false, title="")
png("Value_function_vs_z_2")
