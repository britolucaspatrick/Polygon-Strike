# FPS 3D em Godot 4 - Campeonato 5 vs 5 (GDScript)

Projeto de FPS 3D completo, competitivo e modular desenvolvido em **Godot 4.x** utilizando apenas primitivas 3D (`CSGBox3D`, malhas básicas e física de partículas) sem depender de assets externos.

---

## ⏱️ Etapa de Configuração de Partida (Pré-Jogo)

Antes do tiroteio começar, o jogo abre uma tela central de **Configuração do Campeonato 5v5**:

1. **Duração da Partida (Tempo):**
   - `1 Minuto (Blitz)` | `3 Minutos` | `5 Minutos (Padrão)` | `10 Minutos` | `Ilimitado`
2. **Meta de Abates para Vitória:**
   - `15 Abates` | `25 Abates (Padrão)` | `40 Abates` | `50 Abates`
3. **Controle de Tempo em Jogo:**
   - O relógio é exibido no topo da tela (`⏱️ MM:SS`).
   - Caso o tempo se esgote, a partida é encerrada por tempo e vence quem tiver mais abates/pontos! Se as equipes empatarem, o jogo declara **Empate**.
4. **Botão `▶️ INICIAR PARTIDA`:**
   - Aplica as regras selecionadas, trava o mouse e libera os combatentes e bots para o tiroteio.

---

## 🛒 Mercado de Armas e Munições (Segure a tecla CTRL)

Pressione e segure **CTRL** para abrir o menu do **Mercado Tático**:

- O cursor do mouse é liberado automaticamente para você clicar nos botões de compra.
- Ao soltar **CTRL**, a tela do mercado fecha e o mouse volta a controlar a mira instantaneamente.

### 📍 Restrição de Compra na Base (Zona Segura)
- **Regra:** Compras de armas e reabastecimento de munição só podem ser efetuadas **dentro da SUA Base** (Base Azul, ao sul do mapa, `Z > 44m`). Fora dela ou na base adversária, o mercado fica bloqueado.
- **🚨 Invasão da Base Inimiga (Bônus de $2,000):** Ao avançar pelo mapa e invadir a Base Adversária (Base Vermelha ao norte, `Z < -44m`), você conquista uma recompensa de **+$2,000 de dinheiro**!
- **💖 Regeneração de Vida a 100% na Base:** Ao retornar à Base Aliada, sua barra de vida sobe imediatamente de volta para **100 HP** e permanece cheia com um efeito visual verde de cura!
- **🚫 Bloqueio de Recompra de Munição:** Se suas armas já estiverem com 100% de capacidade (pente e reserva cheios), o botão de *Reabastecer Munição* é bloqueado, evitando gastos desnecessários de dinheiro.
- Se suas munições acabarem no meio da arena, você receberá o aviso:  
  **`⚠️ RETORNE À BASE PARA COMPRAR MUNIÇÃO OU ARMAS!`**
- Um indicador no canto inferior direito do HUD informa se você está **NA BASE** (Mercado & Cura Ativos) ou **EM COMBATE** (Retorne à Base).

### 💰 Economia do Jogo
- Saldo inicial: **$1,200**
- Recompensa por acerto de tiro: **+$15**
- Recompensa por abate inimigo: **+$300**

---

## 🔫 Arsenal Disponível

| Categoria | Arma | Preço | Dano Base | Pente / Reserva | Cadência |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Pistola** | Pistola 9mm | *Inicial ($0)* | 22 | 12 / 48 | Semi-automática rápida |
| **Pistola** | Magnum .44 | $500 | 48 | 6 / 24 | Alto impacto (1 tiro na cabeça = morte) |
| **Metralhadora** | Submetralhadora SMG | $1,200 | 18 | 30 / 120 | Tiro contínuo veloz (12 tiros/seg) |
| **Metralhadora** | Rifle de Assalto M4 | $2,000 | 32 | 30 / 90 | Equilibrado, ótimo alcance |
| **Metralhadora** | Metralhadora Pesada LMG | $3,000 | 28 | 60 / 180 | Pente gigante de 60 tiros |
| **Suprimentos** | Granada Fragmentária | $300 | Até 130 em área | Máx. 3 granadas | Detonação em 1.8s (Tecla **F**) |
| **Suprimentos** | Reabastecer Munição | $200 | - | Enche todas as reservas | - |

---

## 💣 Granada Fragmentária (Tecla F)
- Arremessada fisicamente como um projétil 3D balístico (`RigidBody3D`).
- Possui pavio com contagem regressiva de **1.8 segundos**.
- Raio de explosão de **8.5 metros**, com dano por proximidade (até 130 de dano máximo no epicentro, eliminando alvos próximos).
- Efeito visual de onda de choque esférica expansiva e clarão dinâmico.

---

## 📊 Tabela de Pontuação em Tempo Real (Tecla TAB)

Segure a tecla **TAB** a qualquer momento para abrir o **Placar Competitivo**:

- **Você:** Identificado de forma destacada em dourado como **`★ Você`**.
- **Bots com Nomes Aleatórios Únicos:** Sorteados a cada partida (*Ghost, Viper, Reaper, Cobra, Apex, Havoc, Shadow, Vortex...*).
- **Ranking Dinâmico:** Reordenado em tempo real (#1 a #5) com base em abates (K), mortes (D), dano total e pontuação geral.

---

## 🎯 Sistema de Dano em 3 Partes do Corpo (Hitboxes)

| Zona do Corpo | Altura Relativa | Proporção | Multiplicador | Feedback Visual |
| :--- | :--- | :--- | :--- | :--- |
| **Cabeça** | `1.52m a 1.90m` | **20% (Topo)** | **2.2x** | `-Dano HEADSHOT!` vermelho flutuante |
| **Peito / Tronco** | `0.57m a 1.52m` | **50% (Meio)** | **1.0x** | `-Dano PEITO` branco flutuante |
| **Pernas** | `0.00m a 0.57m` | **30% (Base)** | **0.7x** | `-Dano PERNAS` cinza flutuante |

---

## 🔊 Sistema de Áudio Procedural (100% Nativo sem Assets Externos)

O jogo conta com uma engine de áudio em tempo real (`AudioManager`) que sintetiza ondas sonoras digitais (PCM 16-bit) via código, proporcionando imersão total:

- **Tiros Diferenciados:**
  - *Pistola 9mm:* Estalo seco e ágil.
  - *Magnum .50:* Estrondo grave de alto calibre.
  - *Submetralhadora SMG:* Cadência veloz e estalo rápido.
  - *Rifle M4 / LMG:* Disparo encorpado e potente.
- **Áudio Espacial 3D com Atenuação por Distância:**
  - Os disparos dos **9 bots** espalhados pela arena de 130m possuem posicionamento 3D real (`AudioStreamPlayer3D`), permitindo identificar a direção e distância dos tiroteios pelo fone de ouvido.
- **Detonação de Granada:** Estrondo de impacto e decaimento em baixa frequência com alcance estendido.
- **Feedback de Combate:**
  - *Hitmarker Tick:* Som clássico ao acertar qualquer tiro.
  - *Headshot Bell:* Som nítido metálico/harmônico ao acertar a cabeça (20% topo).
  - *Eliminação Confirmada:* Tom triunfante ao abater um adversário.
- **Efeitos Táticos e de Interface:**
  - Som de recarga mecânica de cartuchos (`R`).
  - Clique seco ao tentar atirar sem munição.
  - Arremesso de granada (`F`).
  - Passos sutis ao caminhar e correr.
  - Toque de caixa registradora/moedas ao comprar no mercado (`CTRL`).
  - Sinal sonoro de erro ao tentar compras inválidas ou com munição cheia.
  - Arpeggio harmônico suave de regeneração ao entrar na base.

---

## 🎮 Controles do Jogo

| Ação | Tecla / Controle |
| :--- | :--- |
| **Mover** | `W`, `A`, `S`, `D` |
| **Correr (Sprint)** | `Shift` |
| **Pular** | `Espaço` |
| **Atirar (Hitscan)** | `Botão Esquerdo do Mouse` |
| **Recarregar Arma** | `R` |
| **Lançar Granada** | `F` |
| **Mercado Tático / Loja** | `CTRL` (Segure para abrir, solte para fechar) |
| **Tabela de Pontuação / Ranking** | `TAB` (Segure para exibir) |
| **Trocar de Arma (Slots)** | `1` (Primária/Metralhadora), `2` (Secundária/Pistola), `3` (Faca/Padrão) |
| **Liberar / Travar Mouse** | `ESC` |
| **Reiniciar Partida** | `F3` |

---

## 🚀 Como Rodar no Godot 4

1. Abra o **Godot Engine 4** e carregue o projeto na pasta `jogotiro`.
2. Pressione **F5** para iniciar.
3. Se estiver na sua base, segure **CTRL** para comprar armas melhores ou granadas com seu dinheiro.
4. Quando a munição de reserva acabar em combate, retorne à Base Azul para reabastecer no Mercado!
