# Zonkey ローカルビルド手順書

ZMK ファームウエアをローカル（WSL2 / Nix）でビルドするための手順と、バージョン固定の方針をまとめたもの。

## 1. 構成

リポジトリは 2 つに分かれている。

```
zmk-workspace/                               ← ビルド環境（このリポジトリ）
├── flake.nix / flake.lock                     ツールチェーン定義・固定
├── Justfile                                   build / flash / draw / init のレシピ
├── .devcontainer/                             Nix を使わない場合の代替環境
├── config/
│   └── zmk-config-zonkey-3DPencoder-DYA/    ← キーマップ（別リポジトリ・gitignore 済み）
│       ├── config/west.yml                    ZMK 本体とモジュールの取得先・版
│       ├── config/zonkey.keymap               キーマップ（keymap editor が編集）
│       ├── config/boards/shields/zonkey /     シールド定義（※末尾に半角スペース有り）
│       └── build.yaml                         ビルドターゲット一覧
├── zmk/ zephyr/ modules/                      west が取得（gitignore 済み）
├── .build/                                    中間生成物（gitignore 済み）
└── firmware/<config名>/*.uf2                  成果物（gitignore 済み）
```

- **zmk-workspace**: `yokomine1701/zmk-workspace`（`upstream` = `kot149/zmk-workspace`）
- **config**: `yokomine1701/zmk-config-zonkey-3DPencoder-DYA`

キーマップを変えたいときは config 側、ビルドが通らないときは workspace 側を触る。

## 2. 前提

| ルート | 必要なもの | 備考 |
|---|---|---|
| Nix | nix（flakes 有効）, direnv | 高速。`flake.lock` でツールチェーンまで完全固定 |
| Dev Container | Docker, VSCode | ZMK 公式イメージを使うので `flake.nix` に依存しない |

- **WSL2 では必ず WSL ネイティブ領域**（`/home/...`）に置く。`/mnt/c/` 配下はビルドが極端に遅くなる。

## 3. 新しい環境でのセットアップ

### Nix ルート

```bash
git clone git@github.com:yokomine1701/zmk-workspace.git
cd zmk-workspace
git clone git@github.com:yokomine1701/zmk-config-zonkey-3DPencoder-DYA.git config/
direnv allow                                        # または nix develop
just init config/zmk-config-zonkey-3DPencoder-DYA   # 初回のみ（west の取得で10分程度）
just build all
```

`just init` は `.west` を作り直し、`west update` で ZMK・Zephyr・各モジュールを取得し、
`west zephyr-export` で CMake パッケージレジストリに Zephyr を登録するところまで行う。

### Dev Container ルート

```bash
git clone git@github.com:yokomine1701/zmk-workspace.git
cd zmk-workspace
git clone git@github.com:yokomine1701/zmk-config-zonkey-3DPencoder-DYA.git config/
code .      # 「Reopen in Container」を選択
just init config/zmk-config-zonkey-3DPencoder-DYA
just build all
```

`just flash` は WSL / macOS 専用なので、コンテナ内ではビルドのみ。`firmware/` の uf2 を手動でコピーする。

## 4. 日常のコマンド

```bash
cd ~/develop/zmk_dev/zmk-workspace   # direnv が自動で Nix シェルに入る

just list                 # ビルドターゲット一覧
just build zonkey_L       # 部分一致で絞り込み（Tab 補完あり）
just build all            # 全ターゲット
just flash zonkey_L       # 書き込み
just flash zonkey_L -r    # ビルドしてから書き込み
just draw                 # キーマップ SVG を生成
just update               # west.yml を変更した後
just clean                # .build と firmware を削除
just clean-all            # .west と zmk も削除（init のやり直し）
```

### このリポジトリのビルドターゲット

| ターゲット | 用途 |
|---|---|
| `zonkey_L rgbled_adapter` | 左手側 |
| `zonkey_R rgbled_adapter` + `studio-rpc-usb-uart` | 右手側（ZMK Studio 有効） |
| `settings_reset` | 設定リセット用（ペアリング情報の消去など） |

成果物は `firmware/zmk-config-zonkey-3DPencoder-DYA/<ターゲット>.uf2`。

## 5. 書き込み

```bash
just flash zonkey_L
```

WSL では PowerShell 経由で `flash.ps1` が走る。挙動は次の通り。

1. 既存ドライブから UF2 ローダー（`INFO_UF2.TXT` があるか、ボリューム名に `UF2` を含む）を探す
2. 見つからなければ**新しいドライブが現れるまで待機**する（`q` でキャンセル）
3. 見つけ次第 uf2 をコピー

つまり**先にコマンドを実行してから**キーボードをブートローダーモード（リセットボタン 2 回押し）にしてもよい。
左右は別ターゲットなので、それぞれ実行する。手動でやるなら `firmware/` の uf2 をエクスプローラでドライブにコピーしても同じ。

## 6. バージョン固定の方針（重要）

ビルドが突然壊れる原因はほぼすべて「ZMK 本体の版」と「ツールチェーンの版」の不一致。
対応関係は次の通りで、**ZMK を更新したら Zephyr と SDK も合わせる**必要がある。

| 何を | どこで固定 | 現在の値 |
|---|---|---|
| ZMK 本体 | `config/west.yml` の `revision` | `main`（未固定 ← 注意） |
| Zephyr | `flake.nix` の `zephyr.url` | `v4.1.0+zmk-fixes` |
| Zephyr SDK | `flake.nix` の `zephyr.sdk-0_16` | 0.16.9 |
| その他全ツール | `flake.lock` | 固定済み |

### ZMK を更新するときの手順

1. 更新後の ZMK が要求する Zephyr を調べる
   ```bash
   grep -A3 "name: zephyr" zmk/app/west.yml      # 例: revision: v4.1.0+zmk-fixes
   ```
2. その Zephyr に対して ZMK 公式 CI が使っている SDK を調べる
   ```
   https://github.com/zmkfirmware/zmk-docker の <major>.<minor>-branch の
   .github/workflows/containers.yml にある zephyr-sdk-version を見る
   ```
   Zephyr の `SDK_VERSION` ファイルではなく、**こちらに合わせる**（下のトラブルシューティング参照）
3. `flake.nix` の `zephyr.url` と `zephyr.sdk-*` を書き換える
4. `nix flake update zephyr && just clean && just build all`

### `revision: main` を固定すべき理由

`config/west.yml` の `revision: main` は追従先が動くため、別環境・別時期にビルドすると
別バージョンの ZMK が降ってきて `flake.nix` の固定と食い違う。これを防ぐにはコミット SHA を書く。

```yaml
    - name: zmk
      remote: zmkfirmware
      revision: 4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85   # 2026-10-09 時点
      import: app/west.yml
```

固定するとローカル・GitHub Actions・keymap editor のすべてで同じ版が使われる。

## 7. トラブルシューティング

実際に遭遇したエラーと対処。

### `Could not find a package configuration file provided by "Zephyr"`

`west zephyr-export` が済んでいない。`just init <config>` を完走させる（`~/.cmake/packages/Zephyr` が作られる）。
`west update` は全モジュールの取得に 10 分程度かかるので、途中で中断していないか確認する。

### `FileNotFoundError: ... 'protoc'`（nanopb_pb2.py の生成で失敗）

ZMK Studio（`studio-rpc-usb-uart` スニペット）を使うターゲットは nanopb が protoc を要求する。
`flake.nix` で `grpcio-tools` と `protobuf` を `PYTHONPATH` に通してある（nanopb は protoc 単体より
grpcio-tools を優先して使う）。Dev Container では公式イメージに同梱されているため不要。

### `conflicting types for '__lock___libc_recursive_mutex'`（picolibc）

**Zephyr と SDK の組み合わせ違い。** Zephyr 4.1 の `lib/libc/picolibc/locks.c` は `_LOCK_T` を
`void *` に再定義して `K_MUTEX_DEFINE` するが、SDK 0.17.2 以降の新しい picolibc は同じシンボルを
`struct __lock` として宣言するため衝突する。

`zephyr/SDK_VERSION` には `0.17.0` と書かれているが、**ZMK 公式 CI が使うのは 0.16.9**
（`zmk-docker` の `4.1-branch`）。Zephyr の記載ではなく ZMK 公式に合わせる。

### `error: attribute 'sphinx-lint' missing`（nix develop の評価エラー）

旧 `urob/zephyr-nix` は Zephyr 4.1 の requirements を解決できない。
現在の上流である `github:nix-community/zephyr-nix` を使う（`flake.nix` で対応済み）。

### `No matching targets found`

`just build` の引数が `build.yaml` のどのターゲットにも部分一致していない。`just list` で確認する。

### ビルドが極端に遅い

ワークスペースが `/mnt/c/` 配下にある。WSL ネイティブ領域に移す。

## 8. 本家の更新を取り込む

```bash
git fetch upstream
git merge upstream/main
```

`flake.nix` は本家と差分があるので、競合したら上の「バージョン固定の方針」の表を見て解決する。

## 9. その他のメモ

- シールドのディレクトリ名は `config/boards/shields/zonkey `（**末尾に半角スペース**）。
  ビルドには影響しないが、将来トラブルの種になり得る。
- `config/west.yml` のモジュールは `path:` 未指定のため、west がワークスペース直下に clone する
  （`zmk-pmw3610-driver` など）。`.gitignore` 済み。
- keymap editor は GitHub 上の config を直接コミットする。ローカルで触る前に
  `git -C config/zmk-config-zonkey-3DPencoder-DYA pull` を忘れないこと。
- `just draw` は config 側の `keymap-drawer/zonkey.svg` を上書きする。
