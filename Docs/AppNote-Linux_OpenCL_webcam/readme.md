This appnote is written with [Asciidoctor](https://asciidoctor.org/docs/user-manual/) a flavour of markdown that can be rendered into HTML or PDF.

## Installing Asciidoctor
```bash
$ sudo apt install asciidoctor
# required to render to pdf
$ gem install asciidoctor-pdf --pre
# required for syntax highlighting
$ gem install rouge 
```

## Rendering the source file
```bash
$ asciidoctor linux_opencl_webcam.adoc
$ asciidoctor-pdf linux_opencl_webcam.adoc
```