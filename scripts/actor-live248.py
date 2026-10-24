import pathlib,subprocess,os
R=pathlib.Path(__file__).resolve().parents[1]
def read(p):return (R/p).read_text()
def decl(s,mark):
 start=s.index(mark);a=s.index('{',start);depth=1;i=a+1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[start:i]
sdk=read('AVDB/Services/JavDBSDK.swift');model=read('AVDB/Models/Movie.swift')
# Exact production declarations, not rewritten response models or injected rows.
parts=['import Foundation',read('AVDB/Models/JSONFlex.swift'),decl(read('AVDB/Models/User.swift'),'public struct User:'),read('AVDB/Networking/JavDBSignature.swift'),read('AVDB/Networking/APIClient.swift'),decl(model,'public struct Actor:'),decl(sdk,'public struct ActorListData:'),read('AVDB/Services/ActorAliasCatalog.swift')]
header=sdk[sdk.index('@MainActor\npublic final class JavDBSDK'):sdk.index('    // Memory only')]
parts.append(header+decl(sdk,'    public func searchActors(')+'\n}')
resolver=read('AVDB/Services/ExternalActorResolver.swift').split('enum ActorAvatarLookupStatus:')[0].replace('import Security','').replace('import SwiftUI','')
parts.append(resolver)
regression = os.environ.get('ACTOR_REGRESSION') == '1'
source=read('AVDB/Services/JavVerseSource.swift')
parts.append(decl(source,'struct JavVerseEntry:')+'}\n'+decl(source,'enum JavVerseFailure:')+'\n'+decl(source,'@MainActor final class JavVerseMapper'))
policy=read('AVDB/Services/JavVersePolicy.swift')
parts.append(decl(policy,'@MainActor enum JavVerseMovieResolver'))
parts.append(decl(policy,'@MainActor enum JavVerseActorResolver'))
parts.append(read('scripts/ActorResolverRegression248.swift' if regression else 'scripts/ActorLive248.swift'))
p=pathlib.Path(os.environ.get('RUNNER_TEMP','/tmp'))/('ActorRegression248.swift' if regression else 'ActorLive248.swift');p.write_text('\n'.join(parts));binary=p.with_suffix('')
subprocess.run(['swiftc','-parse-as-library',str(p),'-o',str(binary)],check=True)
subprocess.run([str(binary),str(R/'AVDB/Resources/ActorAliasIndex.json'),str(R/'scripts/actor-live248-replay.json'),str(R/'AVDB/Resources/JavVerseSnapshot.json')],check=True)
