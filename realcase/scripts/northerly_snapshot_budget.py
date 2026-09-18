#!/usr/bin/env python
"""Meridional-momentum budget of the shallow northerly from high-frequency snapshots (X22: 5-min frames) + the 30-min WRFlux means.
Question: which term accelerates the near-surface northerly over the Karwendel, the crests and the sunlit lee slope between 13:05 and 14:00 UT?
Zone x layer means (zones as northerly_onset_timing.py; layers 0-150 and 150-400 m AGL). Units 1e-4 m/s2; v<0 is northerly, so a NEGATIVE term strengthens it.
 TEND  from the zone-layer mean v of the first and last frame of the window (exact)
 PGF   -alpha*dp/dy at constant height, discretised as the model does: one-dy difference along eta at the v-point minus (dp/dz)*(dz/dy|eta), averaged to mass points
 ADVh  -(u dv/dx + v dv/dy) at constant height; ADVz -w dv/dz   (instantaneous fields, mean over the window's frames; contains the resolved eddies as spatial covariance)
 COR   -f u
 SGSz  -(d/dz) of the closure's vertical flux VW_SGS_MEAN, layer mean = -(F(top)-F(surface))/depth, from the 30-min mean file (only for windows ending 13:30/14:00)
 RES   TEND - (PGF+ADVh+ADVz+COR+SGSz): horizontal SGS, filter, discretisation, sampling
Usage: python northerly_snapshot_budget.py [RUN=X22] [HH:MM-HH:MM ...]   (windows must start/end on existing frames; SGSz only for 30-min windows ending on a mean file)"""
import sys, glob, numpy as np, netCDF4 as nc, warnings; warnings.filterwarnings("ignore")
D="/gpfs/data/fs72996/ewahl"; run=sys.argv[1] if len(sys.argv)>1 else "X22"; A=sorted(glob.glob(f"{D}/exp/{run}/wrf_output/*/"))[-1]
fr={f.split("d01_")[1][11:16]:f for f in sorted(glob.glob(A+"wrfout_d01_*.nc"))}; RD,KAP=287.04,0.2854
g=nc.Dataset(next(iter(fr.values()))); la,lo,hg=[np.asarray(g[k][0]) for k in ("XLAT","XLONG","HGT")]; dx=float(g.DX)
lonb=(lo>11.30)&(lo<11.85); dhdy=np.gradient(hg,dx,axis=0)
Z={"KARW":lonb&(la>47.42)&(la<47.58),"CREST":lonb&(la>47.27)&(la<47.42)&(hg>1800),"LEE":lonb&(la>47.25)&(la<47.40)&(dhdy>np.tan(np.radians(8.5)))&(hg>800)&(hg<2000),"FLOOR":lonb&(la>47.22)&(la<47.40)&(hg<700)}
jj,ii=np.where(lonb&(la>47.20)&(la<47.60)); H=3; J=slice(jj.min()-H,jj.max()+1+H); I=slice(ii.min()-H,ii.max()+1+H); Js=slice(J.start,J.stop+1); Is=slice(I.start,I.stop+1)
hgs=hg[J,I]; fcor=np.asarray(g["F"][0,J,I]); g.close(); Zs={k:m[J,I][1:-1,1:-1] for k,m in Z.items()}; hin=hgs[1:-1,1:-1]
LAY=((0,150),(150,400))
def terms(f):
    d=nc.Dataset(f); ph=(np.asarray(d["PH"][0,:,J,I],dtype="f8")+np.asarray(d["PHB"][0,:,J,I],dtype="f8"))/9.81; z=0.5*(ph[:-1]+ph[1:]); p=np.asarray(d["P"][0,:,J,I],dtype="f8")+np.asarray(d["PB"][0,:,J,I],dtype="f8")
    th=np.asarray(d["T"][0,:,J,I],dtype="f8")+300; qv=np.asarray(d["QVAPOR"][0,:,J,I],dtype="f8"); U=np.asarray(d["U"][0,:,J,Is],dtype="f8"); V=np.asarray(d["V"][0,:,Js,I],dtype="f8"); W=np.asarray(d["W"][0,:,J,I],dtype="f8"); d.close()
    u=0.5*(U[:,:,:-1]+U[:,:,1:]); v=0.5*(V[:,:-1]+V[:,1:]); w=0.5*(W[:-1]+W[1:]); T=th*(p/1e5)**KAP; rho=p/(RD*T*(1+0.61*qv))
    def ddz(a): o=np.empty_like(a); o[1:-1]=(a[2:]-a[:-2])/(z[2:]-z[:-2]); o[0]=(a[1]-a[0])/(z[1]-z[0]); o[-1]=(a[-1]-a[-2])/(z[-1]-z[-2]); return o
    dpdz=ddz(p); pgv=-(2.0/(rho[:,:-1]+rho[:,1:]))*((p[:,1:]-p[:,:-1])/dx-0.5*(dpdz[:,:-1]+dpdz[:,1:])*(z[:,1:]-z[:,:-1])/dx)   # at v-points j+1/2
    pgf=0.5*(pgv[:,:-1]+pgv[:,1:])[:,:,1:-1]                                                                                    # mass points j=1..ny-2, interior i
    dvdz=ddz(v); vy=((v[:,2:]-v[:,:-2])/(2*dx)-dvdz[:,1:-1]*(z[:,2:]-z[:,:-2])/(2*dx))[:,:,1:-1]; vx=((v[:,:,2:]-v[:,:,:-2])/(2*dx)-dvdz[:,:,1:-1]*(z[:,:,2:]-z[:,:,:-2])/(2*dx))[:,1:-1]
    c=(slice(None),slice(1,-1),slice(1,-1)); return dict(v=v[c],agl=z[c]-hin[None],pgf=pgf,advh=-(u[c]*vx+v[c]*vy),advz=-(w[c]*dvdz[c]),cor=-(fcor[1:-1,1:-1][None]*u[c]))
def zl(t,key,m,a,b): wt=(t["agl"][:,m]>=a)&(t["agl"][:,m]<b); return float((t[key][:,m]*wt).sum()/max(wt.sum(),1))
def sgs(tend,m,a,b):
    f=glob.glob(A+f"meanout_d01_2025-07-17_{tend}:00.nc")
    if not f: return np.nan
    d=nc.Dataset(f[0]); F=np.asarray(d["VW_SGS_MEAN"][0,:,J,I],dtype="f8")[:,1:-1,1:-1][:,m]; zw=np.asarray(d["Z_MEAN"][0,:,J,I],dtype="f8")[:,1:-1,1:-1][:,m]-hin[m][None]; d.close()
    out=[]
    for c in range(F.shape[1]):
        fa,fb=np.interp([a,b],zw[:,c],F[:,c]); out.append(-(fb-fa)/(b-a))
    return float(np.mean(out))
T={t:terms(f) for t,f in fr.items()}; times=sorted(T)
print(f"{run}: meridional momentum budget, zone x layer means, 1e-4 m/s2 (negative = strengthens the northerly). v0->v1 = zone-layer mean v at window start/end [m/s].")
WIN=[tuple(a.split("-")) for a in sys.argv[2:]] or [("13:05","13:15"),("13:15","13:30"),("13:30","14:00")]
for w0,w1 in WIN:
    ts=[t for t in times if w0<=t<=w1]; dt=(int(w1[:2])*60+int(w1[3:])-int(w0[:2])*60-int(w0[3:]))*60.
    print(f"\n=== window {w0}-{w1} UT ({len(ts)} frames)\nzone   layer     v0->v1      TEND |    PGF   ADVh   ADVz    COR   SGSz |    RES")
    for zn,m in Zs.items():
        for a,b in LAY:
            v0,v1=zl(T[w0],"v",m,a,b),zl(T[w1],"v",m,a,b); tend=(v1-v0)/dt; mean=lambda k: np.mean([zl(T[t],k,m,a,b) for t in ts])
            pg,ah,az,co=mean("pgf"),mean("advh"),mean("advz"),mean("cor"); sg=sgs(w1,m,a,b) if (w1[3:] in ("00","30") and (int(w1[:2])*60+int(w1[3:])-int(w0[:2])*60-int(w0[3:]))<=30) else np.nan; res=tend-(pg+ah+az+co+(0 if np.isnan(sg) else sg))
            print(f"{zn:6s} {a:3d}-{b:3d}  {v0:+5.2f}->{v1:+5.2f}  {tend*1e4:+6.2f} | {pg*1e4:+6.2f} {ah*1e4:+6.2f} {az*1e4:+6.2f} {co*1e4:+6.2f} {sg*1e4:+6.2f} | {res*1e4:+6.2f}")
if len(sys.argv)<=2: print("\nscatter of the instantaneous PGF zone-layer mean over the frames of 13:30-14:00 (std, 1e-4 m/s2): "+", ".join(f"{zn} {np.std([zl(T[t],'pgf',m,0,150) for t in times if '13:30'<=t<='14:00'])*1e4:.1f}" for zn,m in Zs.items()))
