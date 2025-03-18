# step-security/reviewdog-action-setup

This action installs :dog: [reviewdog](https://github.com/reviewdog/reviewdog).

## Input
```yaml
inputs:
  reviewdog_version:
    description: 'reviewdog version. [latest,nightly,vX.Y.Z]'
    default: 'latest'
```

## Usage

### Latest
```yaml
steps:
  - uses: step-security/reviewdog-action-setup@v1
  - run: reviewdog -version
```

### Specify reviewdog version
```yaml
steps:
  - uses: step-security/reviewdog-action-setup@v1
    with:
      reviewdog_version: v0.20.3
  - run: reviewdog -version
```

### Nightly
```yaml
steps:
  - uses: step-security/reviewdog-action-setup@v1
    with:
      reviewdog_version: nightly
  - run: reviewdog -version
```
