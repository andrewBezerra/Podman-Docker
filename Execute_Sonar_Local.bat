dotnet sonarscanner begin /k:"Covenant" /d:sonar.host.url="http://localhost:9000"  /d:sonar.login="squ_c7c994088cfaedba925d1beeb360c9c12f4dc7cc"  /d:sonar.cs.vscoveragexml.reportsPaths=coverage.xml /d:sonar.scanner.scanAll=false

dotnet build .\src\Jazz.Covenant.sln

dotnet-coverage collect "dotnet test .\src\Jazz.Covenant.sln" -f xml -o "coverage.xml"

dotnet sonarscanner end /d:sonar.login="squ_c7c994088cfaedba925d1beeb360c9c12f4dc7cc"

