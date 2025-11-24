#!/bin/bash

echo "=== INSTALADOR DO EXPORTADOR EPE WEBMAP ==="
echo "Sistema: Debian Minimal"
echo "==========================================="

# Verificar se é root
#if [ "$EUID" -eq 0 ]; then
#    echo "❌ Não execute como root. Use um usuário normal."
#    exit 1
#fi

# Atualizar sistema
echo "📦 Atualizando sistema..."
apt update
apt upgrade -y

# Instalar dependências do sistema
echo "📦 Instalando dependências do sistema..."
apt install -y python3 python3-pip python3-venv curl wget git unzip

# Criar diretório do projeto
mkdir -p epe_webmap_exporter
cd epe_webmap_exporter

# Criar ambiente virtual
echo "🐍 Criando ambiente virtual Python..."
python3 -m venv venv
source venv/bin/activate

# Instalar dependências Python
echo "📚 Instalando dependências Python..."
pip install --upgrade pip
pip install requests simplekml

# Criar arquivos de script
echo "📄 Criando scripts..."

# Criar requirements.txt
cat > requirements.txt << 'EOF'
requests>=2.31.0
simplekml>=1.3.6
urllib3>=1.26.0
EOF

# Baixar scripts principais
echo "📥 Baixando scripts principais..."

# Criar exportar_dados.py
cat > exportar_dados.py << 'EOF'
import requests
import json
import os
import time
import sys

class EPEWebMapExporter:
    def __init__(self):
        self.base_url = "https://gisepeprd2.epe.gov.br/arcgis/rest/services/SMA/WMS_Webmap_EPE/MapServer"
        self.session = requests.Session()
        # Configurar headers para evitar bloqueios
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
            'Accept': 'application/json'
        })
        
    def get_layer_info(self, layer_id):
        """Obtém informações sobre uma camada específica"""
        url = f"{self.base_url}/{layer_id}?f=json"
        try:
            print(f"    📡 Obtendo informações da camada {layer_id}...")
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            return response.json()
        except Exception as e:
            print(f"    ❌ Erro ao obter informações da camada {layer_id}: {e}")
            return None
    
    def query_layer_features_paginated(self, layer_id, out_fields="*", where="1=1"):
        """Consulta features com paginação para evitar limite de 2000"""
        all_features = []
        offset = 0
        page_size = 1000
        
        print(f"    🔍 Consultando features da camada {layer_id}...")
        
        while True:
            query_url = f"{self.base_url}/{layer_id}/query"
            
            params = {
                'where': where,
                'outFields': out_fields,
                'returnGeometry': 'true',
                'f': 'json',
                'outSR': '4326',
                'resultOffset': offset,
                'resultRecordCount': page_size,
                'returnIdsOnly': 'false'
            }
            
            try:
                response = self.session.get(query_url, params=params, timeout=60)
                response.raise_for_status()
                data = response.json()
                
                if 'features' in data and data['features']:
                    features_count = len(data['features'])
                    all_features.extend(data['features'])
                    print(f"      📄 Página {offset//page_size + 1}: {features_count} features")
                    
                    # Verifica se há mais features
                    if features_count < page_size:
                        break
                    
                    offset += page_size
                    time.sleep(0.5)  # Delay entre páginas
                else:
                    break
                    
            except Exception as e:
                print(f"      ❌ Erro na página {offset//page_size + 1}: {e}")
                break
        
        return {'features': all_features}
    
    def export_all_layers_to_arcgis_format(self, output_dir="epe_data"):
        """Exporta todas as camadas no formato ArcGIS"""
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)
        
        # Lista de todas as camadas (0 a 109)
        layers_to_export = list(range(0, 110))
        
        successful_exports = []
        total_features = 0
        
        print("🚀 Iniciando exportação de dados da EPE...")
        print("📋 Este processo pode demorar 30-60 minutos...")
        print("💾 Os dados serão salvos em formato ArcGIS REST\n")
        
        for layer_id in layers_to_export:
            print(f"🎯 Processando camada {layer_id}...")
            
            # Obtém informações da camada
            layer_info = self.get_layer_info(layer_id)
            if not layer_info:
                continue
            
            layer_type = layer_info.get('type', 'desconhecido')
            layer_name = layer_info.get('name', f'layer_{layer_id}').replace('/', '_').replace('\\', '_')
            
            # Para Group Layers, salva apenas metadados
            if layer_type == 'Group Layer':
                group_info = {
                    'id': layer_id,
                    'name': layer_name,
                    'type': layer_type,
                    'subLayerIds': layer_info.get('subLayerIds', [])
                }
                
                filename = f"{output_dir}/grupo_{layer_id:03d}_{layer_name}.json"
                with open(filename, 'w', encoding='utf-8') as f:
                    json.dump(group_info, f, ensure_ascii=False, indent=2)
                
                print(f"  📁 Grupo {layer_id} salvo: {layer_name}")
                continue
                
            # Para Raster Layers, salva apenas metadados
            if layer_type == 'Raster Layer':
                raster_info = {
                    'id': layer_id,
                    'name': layer_name,
                    'type': layer_type
                }
                
                filename = f"{output_dir}/raster_{layer_id:03d}_{layer_name}.json"
                with open(filename, 'w', encoding='utf-8') as f:
                    json.dump(raster_info, f, ensure_ascii=False, indent=2)
                
                print(f"  🖼️  Raster {layer_id} salvo: {layer_name}")
                continue
            
            # Para Feature Layers, exporta os dados
            if layer_type == 'Feature Layer':
                features_data = self.query_layer_features_paginated(layer_id)
                
                if features_data and 'features' in features_data and len(features_data['features']) > 0:
                    # Salva no formato ArcGIS REST (mantém estrutura original)
                    filename = f"{output_dir}/camada_{layer_id:03d}_{layer_name}.json"
                    
                    with open(filename, 'w', encoding='utf-8') as f:
                        json.dump(features_data, f, ensure_ascii=False, indent=2)
                    
                    feature_count = len(features_data['features'])
                    total_features += feature_count
                    
                    print(f"  ✅ Camada {layer_id} exportada: {feature_count} features")
                    
                    successful_exports.append({
                        'id': layer_id,
                        'name': layer_name,
                        'type': layer_type,
                        'filename': filename,
                        'feature_count': feature_count
                    })
                else:
                    print(f"  ⚠️  Camada {layer_id} sem features ou erro na consulta")
                    
                    # Salva informações mesmo sem features
                    empty_info = {
                        'id': layer_id,
                        'name': layer_name,
                        'type': layer_type,
                        'features': 0
                    }
                    
                    filename = f"{output_dir}/vazia_{layer_id:03d}_{layer_name}.json"
                    with open(filename, 'w', encoding='utf-8') as f:
                        json.dump(empty_info, f, ensure_ascii=False, indent=2)
            else:
                print(f"  ❓ Tipo desconhecido: {layer_type} para camada {layer_id}")
            
            # Delay para não sobrecarregar o servidor
            time.sleep(1)
        
        return successful_exports, total_features

def main():
    exporter = EPEWebMapExporter()
    
    try:
        results, total_features = exporter.export_all_layers_to_arcgis_format()
        
        print(f"\n🎉 EXPORTAÇÃO CONCLUÍDA!")
        print(f"📈 Camadas Feature Layer exportadas: {len(results)}")
        print(f"📊 Total de features: {total_features:,}")
        
        # Salva relatório
        report = {
            'total_layers_exported': len(results),
            'total_features': total_features,
            'exported_layers': results,
            'timestamp': time.strftime('%Y-%m-%d %H:%M:%S')
        }
        
        with open("relatorio_exportacao.json", 'w', encoding='utf-8') as f:
            json.dump(report, f, ensure_ascii=False, indent=2)
        
        print(f"📄 Relatório salvo: relatorio_exportacao.json")
        print(f"👉 Próximo passo: Execute 'python3 criar_kmz.py'")
        
    except KeyboardInterrupt:
        print(f"\n⏹️  Exportação interrompida pelo usuário")
    except Exception as e:
        print(f"\n💥 ERRO CRÍTICO: {e}")

if __name__ == "__main__":
    main()
EOF

# Criar criar_kmz.py
cat > criar_kmz.py << 'EOF'
import simplekml
import json
import glob
import os
import sys
from datetime import datetime

def extract_arcgis_geometry(geometry):
    """Extrai geometrias do formato ArcGIS REST"""
    if not geometry:
        return None, None
    
    # Ponto: formato {"x": lon, "y": lat}
    if 'x' in geometry and 'y' in geometry:
        return [(geometry['x'], geometry['y'])], 'point'
    
    # Linha: formato {"paths": [[[lon,lat], [lon,lat], ...]]}
    elif 'paths' in geometry and geometry['paths']:
        paths = geometry['paths']
        if paths and len(paths) > 0:
            first_path = paths[0]
            line_coords = []
            for coord in first_path:
                if isinstance(coord, list) and len(coord) >= 2:
                    line_coords.append((coord[0], coord[1]))
            return line_coords, 'linestring'
    
    # Polígono: formato {"rings": [[[lon,lat], [lon,lat], ...]]}
    elif 'rings' in geometry and geometry['rings']:
        rings = geometry['rings']
        if rings and len(rings) > 0:
            exterior_ring = rings[0]  # Primeiro ring é o exterior
            poly_coords = []
            for coord in exterior_ring:
                if isinstance(coord, list) and len(coord) >= 2:
                    poly_coords.append((coord[0], coord[1]))
            # Fecha o polígono se necessário
            if len(poly_coords) >= 3 and poly_coords[0] != poly_coords[-1]:
                poly_coords.append(poly_coords[0])
            return poly_coords, 'polygon'
    
    # Multiponto: formato {"points": [[lon,lat], [lon,lat], ...]}
    elif 'points' in geometry and geometry['points']:
        points = geometry['points']
        point_coords = []
        for point in points:
            if isinstance(point, list) and len(point) >= 2:
                point_coords.append((point[0], point[1]))
        return point_coords, 'multipoint'
    
    return None, None

def format_attribute_value(value):
    """Formata valores de atributos para exibição"""
    if value is None:
        return ""
    
    # Converte timestamp do ArcGIS para data legível
    if isinstance(value, (int, float)) and value > 1000000000000:
        try:
            return datetime.fromtimestamp(value/1000).strftime('%Y-%m-%d')
        except:
            pass
    
    # Trunca strings muito longas
    str_value = str(value)
    if len(str_value) > 100:
        return str_value[:100] + "..."
    
    return str_value

def create_description(attributes):
    """Cria descrição formatada para os placemarks"""
    if not attributes:
        return "Sem propriedades disponíveis"
    
    try:
        desc = "<![CDATA[<div style='font-family: Arial; font-size: 12px; max-width: 500px;'>"
        desc += "<h3 style='color: #2E86AB; margin-bottom: 10px;'>Propriedades</h3>"
        desc += "<table style='border-collapse: collapse; width: 100%; font-size: 11px; border: 1px solid #ddd;'>"
        
        # Ordena as propriedades para melhor visualização
        sorted_attrs = sorted(attributes.items())
        
        for key, value in sorted_attrs:
            formatted_value = format_attribute_value(value)
            if formatted_value:
                desc += f"<tr style='border-bottom: 1px solid #eee;'>"
                desc += f"<td style='padding: 6px; font-weight: bold; color: #555; background-color: #f9f9f9; width: 40%;'>{key}</td>"
                desc += f"<td style='padding: 6px;'>{formatted_value}</td>"
                desc += "</tr>"
        
        desc += "</table>"
        desc += f"<p style='margin-top: 10px; color: #666; font-size: 10px;'>Exportado em: {datetime.now().strftime('%Y-%m-%d %H:%M')}</p>"
        desc += "</div>]]>"
        return desc
        
    except Exception as e:
        return f"<![CDATA[<div>Erro ao criar descrição: {str(e)}</div>]]>"

def create_kmz_from_arcgis_data():
    """Cria KMZ a partir dos dados no formato ArcGIS"""
    kml = simplekml.Kml()
    kml.document.name = "EPE Webmap - Dados Completos"
    kml.document.description = "Exportação completa do Webmap da EPE contendo sistema elétrico, infraestrutura energética e dados ambientais"
    
    # Encontra todos os arquivos de camadas
    layer_files = glob.glob("epe_data/camada_*.json")
    
    if not layer_files:
        print("❌ Nenhum arquivo de camada encontrado!")
        print("💡 Execute primeiro: python3 exportar_dados.py")
        return
    
    print("🚀 INICIANDO CONVERSÃO PARA KMZ")
    print(f"📁 Encontrados {len(layer_files)} arquivos de camadas")
    print("🎯 Convertendo formato ArcGIS REST para KML...")
    print("⏰ Isso pode demorar vários minutos...\n")
    
    total_features_converted = 0
    layers_with_data = 0
    geometry_statistics = {}
    
    for layer_file in sorted(layer_files):
        try:
            with open(layer_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            layer_name = os.path.basename(layer_file).replace('.json', '')
            folder = kml.newfolder(name=layer_name)
            
            feature_count = 0
            features = data.get('features', [])
            layer_geom_stats = {}
            
            print(f"🔧 Processando {layer_name} ({len(features)} features)...")
            
            for i, feature in enumerate(features):
                try:
                    # Formato ArcGIS: feature tem "attributes" e "geometry"
                    attributes = feature.get('attributes', {})
                    geometry = feature.get('geometry', {})
                    
                    # Detecta tipo de geometria
                    geom_type = 'unknown'
                    if 'x' in geometry and 'y' in geometry:
                        geom_type = 'point'
                    elif 'paths' in geometry:
                        geom_type = 'linestring'
                    elif 'rings' in geometry:
                        geom_type = 'polygon'
                    elif 'points' in geometry:
                        geom_type = 'multipoint'
                    
                    layer_geom_stats[geom_type] = layer_geom_stats.get(geom_type, 0) + 1
                    
                    # Extrai coordenadas
                    coords, final_geom_type = extract_arcgis_geometry(geometry)
                    
                    if coords and final_geom_type:
                        # Cria nome baseado nas propriedades
                        name_keys = ['OBJECTID', 'Name', 'NOME', 'DESCRICAO', 'ID', 'nome', 'leilao', 'ceg', 'CEG']
                        feature_name = f"Feature_{i+1}"
                        for key in name_keys:
                            if key in attributes and attributes[key] is not None:
                                feature_name = str(attributes[key])
                                break
                        
                        # Converte para KML
                        if final_geom_type == 'point':
                            pnt = folder.newpoint(
                                name=feature_name,
                                coords=coords,
                                description=create_description(attributes)
                            )
                            # Estilo para pontos
                            pnt.style.iconstyle.color = simplekml.Color.blue
                            pnt.style.iconstyle.scale = 0.8
                            feature_count += 1
                            
                        elif final_geom_type == 'multipoint':
                            for j, point_coord in enumerate(coords):
                                pnt = folder.newpoint(
                                    name=f"{feature_name}_{j+1}",
                                    coords=[point_coord],
                                    description=create_description(attributes)
                                )
                                pnt.style.iconstyle.color = simplekml.Color.blue
                                pnt.style.iconstyle.scale = 0.6
                            feature_count += len(coords)
                            
                        elif final_geom_type == 'linestring':
                            lin = folder.newlinestring(
                                name=feature_name,
                                coords=coords,
                                description=create_description(attributes)
                            )
                            # Estilo para linhas
                            lin.style.linestyle.color = simplekml.Color.red
                            lin.style.linestyle.width = 2
                            feature_count += 1
                            
                        elif final_geom_type == 'polygon':
                            pol = folder.newpolygon(
                                name=feature_name,
                                outerboundaryis=coords,
                                description=create_description(attributes)
                            )
                            # Estilo para polígonos
                            pol.style.polystyle.color = simplekml.Color.changealpha('80', simplekml.Color.green)
                            pol.style.linestyle.color = simplekml.Color.darkgreen
                            pol.style.linestyle.width = 1
                            feature_count += 1
                            
                except Exception as e:
                    # Continua processando mesmo com erros em features individuais
                    if i < 3:  # Mostra apenas os primeiros erros para evitar spam
                        print(f"    ⚠️  Erro na feature {i}: {str(e)[:80]}...")
                    continue
            
            # Estatísticas da camada
            if layer_geom_stats:
                geometry_statistics[layer_name] = layer_geom_stats
            
            if feature_count > 0:
                print(f"✅ {layer_name}: {feature_count} features convertidas")
                layers_with_data += 1
                total_features_converted += feature_count
            else:
                print(f"❌ {layer_name}: 0 features convertidas")
                
        except Exception as e:
            print(f"💥 ERRO CRÍTICO em {layer_file}: {str(e)}")
    
    # Salva o KMZ
    output_file = "EPE_WEBMAP_COMPLETO.kmz"
    kml.savekmz(output_file)
    
    # Relatório final
    print(f"\n🎉 CONVERSÃO CONCLUÍDA!")
    print(f"📁 Arquivo KMZ: {output_file}")
    print(f"📊 Camadas com dados: {layers_with_data}/{len(layer_files)}")
    print(f"📈 Total de features convertidas: {total_features_converted:,}")
    
    if os.path.exists(output_file):
        size_mb = os.path.getsize(output_file) / (1024 * 1024)
        print(f"💾 Tamanho do KMZ: {size_mb:.1f} MB")
    
    # Salva relatório detalhado
    report = {
        'total_layers_processed': len(layer_files),
        'layers_with_data': layers_with_data,
        'total_features_converted': total_features_converted,
        'file_size_mb': size_mb if os.path.exists(output_file) else 0,
        'geometry_statistics': geometry_statistics,
        'conversion_date': datetime.now().isoformat()
    }
    
    with open('relatorio_conversao_kmz.json', 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
    
    print(f"📄 Relatório salvo: relatorio_conversao_kmz.json")
    
    if layers_with_data > 0:
        print(f"\n🎯 PRONTO! Abra o arquivo '{output_file}' no Google Earth")
    else:
        print(f"\n🔴 Nenhuma feature foi convertida. Verifique os dados de entrada.")

if __name__ == "__main__":
    create_kmz_from_arcgis_data()
EOF

# Criar script de execução
cat > executar_exportacao.sh << 'EOF'
#!/bin/bash

# Ativar ambiente virtual
source venv/bin/activate

echo "=== EXPORTADOR EPE WEBMAP ==="
echo "1. Exportar dados da EPE"
echo "2. Converter para KMZ"
echo "3. Executar processo completo"
echo "4. Sair"

read -p "Escolha uma opção [1-4]: " choice

case $choice in
    1)
        echo "🚀 Iniciando exportação de dados..."
        python3 exportar_dados.py
        ;;
    2)
        echo "🔄 Convertendo para KMZ..."
        python3 criar_kmz.py
        ;;
    3)
        echo "🎯 Executando processo completo..."
        echo "📥 Etapa 1: Exportando dados..."
        python3 exportar_dados.py
        echo "📤 Etapa 2: Convertendo para KMZ..."
        python3 criar_kmz.py
        ;;
    4)
        echo "👋 Saindo..."
        exit 0
        ;;
    *)
        echo "❌ Opção inválida"
        exit 1
        ;;
esac
EOF

chmod +x executar_exportacao.sh

echo ""
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo "📁 Diretório do projeto: $(pwd)"
echo ""
echo "🎯 PRÓXIMOS PASSOS:"
echo "1. Execute: cd epe_webmap_exporter"
echo "2. Execute: ./executar_exportacao.sh"
echo "3. Escolha a opção 3 para processo completo"
echo ""
echo "💡 DICAS:"
echo "   - O processo pode demorar 30-60 minutos"
echo "   - Serão criados ~300MB de dados temporários"
echo "   - O KMZ final terá ~50-200MB"
echo "   - Sempre ative o ambiente virtual: source venv/bin/activate"
echo " Aumentar swap se necessario"
echo "fallocate -l 1G /swapfile"
echo "chmod 600 /swapfile"
echo "mkswap /swapfile"
echo "swapon /swapfile"
