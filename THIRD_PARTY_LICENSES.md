# Third-Party Licenses

Macstral is proprietary software (see [EULA.md](EULA.md)). It depends on and downloads
the following third-party components, each under its own open-source license. Those
licenses apply only to the respective components, not to Macstral itself.

---

## Voxtral models (Mistral AI / mlx-community) — Apache License 2.0

Macstral downloads and runs Voxtral speech models at runtime:

- `mlx-community/Voxtral-Mini-4B-Realtime-2602-4bit` (Fast)
- `mlx-community/Voxtral-Mini-4B-Realtime-6bit` (Balanced)
- `mlx-community/Voxtral-Mini-4B-Realtime-2602-fp16` (Accurate)

These are quantized derivatives of Mistral AI's Voxtral models
(`mistralai/Voxtral-Mini-4B-Realtime-2602`, `mistralai/Voxtral-Mini-3B-2507`),
released by Mistral AI under the Apache License 2.0. The mlx-community builds are
quantized derivative works of those Apache-2.0 models.

> Copyright Mistral AI and the mlx-community contributors.
> Licensed under the Apache License, Version 2.0 (the "License"); you may not use
> these files except in compliance with the License. You may obtain a copy of the
> License at http://www.apache.org/licenses/LICENSE-2.0
>
> Unless required by applicable law or agreed to in writing, software distributed
> under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
> CONDITIONS OF ANY KIND, either express or implied. See the License for the
> specific language governing permissions and limitations under the License.

The full Apache License 2.0 text is available at
<http://www.apache.org/licenses/LICENSE-2.0>.

---

## Qwen2.5 model (Alibaba / mlx-community) — Apache License 2.0

The Audio Notes feature downloads and runs a local language model at runtime to turn
transcripts into notes:

- `mlx-community/Qwen2.5-3B-Instruct-4bit`

This is a quantized derivative of Alibaba Cloud's `Qwen/Qwen2.5-3B-Instruct`, released
under the Apache License 2.0. The mlx-community build is a quantized derivative work of
that Apache-2.0 model.

> Copyright the Qwen team, Alibaba Cloud, and the mlx-community contributors.
> Licensed under the Apache License, Version 2.0. You may obtain a copy of the License at
> http://www.apache.org/licenses/LICENSE-2.0

---

## mlx-lm — MIT License

The Audio Notes feature uses [`mlx-lm`](https://github.com/ml-explore/mlx-lm) (pinned to
`0.28.3`) to run the notes language model on-device via MLX. mlx-lm is distributed by Apple
under the MIT License. The MIT terms below apply.

---

## voxmlx — MIT License

Macstral's bundled inference server (`Macstral/Resources/voxtral_server.py`) imports and
extends [`voxmlx`](https://github.com/T0mSIlver/voxmlx), pinned to commit `48bfdec9`.

```
MIT License

Copyright (c) 2026 Awni Hannun

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## HotKey — MIT License

Macstral uses [HotKey](https://github.com/soffes/HotKey) (Sam Soffes) for global hotkey
registration, under the MIT License. Copyright (c) Sam Soffes. The MIT terms above apply.

---

## Python runtime

Macstral downloads a standalone CPython build from
[python-build-standalone](https://github.com/indygreg/python-build-standalone). CPython is
distributed under the Python Software Foundation License.
