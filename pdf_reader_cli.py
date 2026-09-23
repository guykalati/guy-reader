#!/usr/bin/env python3
"""
Pocket TTS PDF Reader (CLI)
Real-time text-to-speech with live sentence-by-sentence visual follow-along highlight.
"""

import argparse
import os
import re
import sys
import time

try:
    import numpy as np
    import sounddevice as sd
    from pypdf import PdfReader
    from rich.console import Console
    from rich.panel import Panel
    from rich.text import Text
except ImportError:
    print("Missing dependencies! Please run:")
    print("  pip install pocket-tts-onnx sounddevice pypdf rich numpy")
    sys.exit(1)

try:
    from pocket_tts_onnx import PocketTTS
except ImportError:
    print("pocket-tts-onnx not found! Please run:")
    print("  pip install pocket-tts-onnx")
    print("or install from git: pip install git+https://github.com/thewh1teagle/pocket-tts-onnx.git")
    sys.exit(1)

console = Console()

def split_into_sentences(text: str) -> list[str]:
    """Clean and split text into speakable sentences."""
    text = re.sub(r'\s+', ' ', text).strip()
    if not text:
        return []
    # Regex splitting on sentence boundary punctuation
    sentence_endings = re.compile(r'(?<=[.!?])\s+')
    raw_sentences = sentence_endings.split(text)
    sentences = []
    for s in raw_sentences:
        s = s.strip()
        if s and len(s) > 1 and any(c.isalnum() for c in s):
            sentences.append(s)
    return sentences

def extract_pdf_pages(pdf_path: str) -> list[tuple[int, list[str]]]:
    """Extract sentences from each page of a PDF file."""
    reader = PdfReader(pdf_path)
    pages_data = []
    for page_idx, page in enumerate(reader.pages):
        raw_text = page.extract_text() or ""
        sentences = split_into_sentences(raw_text)
        if sentences:
            pages_data.append((page_idx + 1, sentences))
    return pages_data

def play_and_highlight(tts: PocketTTS, pages_data: list[tuple[int, list[str]]], voice: str = "alba"):
    """Stream speech while highlighting the active sentence in real-time."""
    total_pages = len(pages_data)
    
    with sd.OutputStream(samplerate=tts.sample_rate, channels=1, dtype="float32") as speaker:
        for page_num, sentences in pages_data:
            for active_idx, current_sentence in enumerate(sentences):
                # Clear and render page view with highlighting
                console.clear()
                
                doc_text = Text()
                for idx, sent in enumerate(sentences):
                    if idx == active_idx:
                        # Highlight active sentence
                        doc_text.append(f"▶ {sent} ", style="bold yellow on blue")
                    elif idx < active_idx:
                        # Already read sentences
                        doc_text.append(f"{sent} ", style="dim")
                    else:
                        # Upcoming sentences
                        doc_text.append(f"{sent} ", style="white")

                header = f"[bold cyan]Pocket TTS - Reading PDF[/bold cyan] | [green]Page {page_num}/{total_pages}[/green] | [magenta]Sentence {active_idx + 1}/{len(sentences)}[/magenta] | [yellow]Voice: {voice}[/yellow]"
                panel = Panel(
                    doc_text,
                    title=header,
                    subtitle="[dim]Streaming audio in real time (Press Ctrl+C to stop)[/dim]",
                    expand=True,
                    padding=(1, 2),
                )
                console.print(panel)
                
                # Stream frames directly into the sound device
                try:
                    for frame in tts.stream(current_sentence, voice=voice):
                        speaker.write(frame)
                    
                    # Small tail buffer between sentences to prevent audio pop
                    tail_silence = np.zeros(int(tts.sample_rate * 0.08), dtype=np.float32)
                    speaker.write(tail_silence)
                except KeyboardInterrupt:
                    console.print("\n[bold red]Playback stopped by user.[/bold red]")
                    return

def main():
    parser = argparse.ArgumentParser(description="Read a PDF out loud with real-time text highlight using Pocket TTS ONNX.")
    parser.add_argument("pdf", help="Path to the PDF file")
    parser.add_argument("--model", default="pocket-tts-english.onnx", help="Path to the pocket-tts ONNX model file (default: pocket-tts-english.onnx)")
    parser.add_argument("--voice", default="alba", help="Voice to use (default: alba). Available voices depend on model.")
    parser.add_argument("--page", type=int, default=1, help="Start from specific page number (1-indexed)")
    args = parser.parse_args()

    if not os.path.exists(args.pdf):
        console.print(f"[bold red]Error:[/bold red] PDF file '{args.pdf}' not found.")
        sys.exit(1)

    if not os.path.exists(args.model):
        console.print(f"[bold red]Error:[/bold red] Model file '{args.model}' not found.")
        console.print("[yellow]Please download the model first:[/yellow]")
        console.print("  curl -L -o pocket-tts-english.onnx https://github.com/thewh1teagle/pocket-tts-onnx/releases/download/models-v1.0/pocket-tts-english.onnx")
        sys.exit(1)

    console.print(f"[cyan]Loading model '{args.model}'...[/cyan]")
    tts = PocketTTS(args.model)
    available_voices = tts.voices()
    console.print(f"[green]Model loaded![/green] Available voices: {list(available_voices.keys()) if isinstance(available_voices, dict) else available_voices}")

    voice_to_use = args.voice
    if isinstance(available_voices, (list, tuple, dict)) and voice_to_use not in available_voices:
        first_voice = next(iter(available_voices)) if available_voices else "alba"
        console.print(f"[yellow]Voice '{args.voice}' not in list, defaulting to '{first_voice}'[/yellow]")
        voice_to_use = first_voice

    console.print(f"[cyan]Extracting text from '{args.pdf}'...[/cyan]")
    pages_data = extract_pdf_pages(args.pdf)
    if not pages_data:
        console.print("[bold red]No text could be extracted from the PDF.[/bold red]")
        sys.exit(1)

    pages_data = [p for p in pages_data if p[0] >= args.page]
    if not pages_data:
        console.print(f"[bold red]Page {args.page} is beyond total pages in PDF.[/bold red]")
        sys.exit(1)

    console.print(f"[green]Starting reading from Page {args.page}...[/green]\n")
    time.sleep(0.5)
    
    play_and_highlight(tts, pages_data, voice=voice_to_use)
    console.print("\n[bold green]Finished reading document![/bold green]")

if __name__ == "__main__":
    main()
