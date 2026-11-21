package com.azurekiln.qfli.core;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.util.List;

/** Read-only, grant-scoped ZIP provider. Never exposes the parent files/cache tree. */
public final class QfliArchiveProvider extends ContentProvider {
    static Uri uriFor(Context context, String path) throws IOException {
        File root = new File(context.getFilesDir(), "archive_shares").getCanonicalFile();
        File file = new File(path).getCanonicalFile();
        String prefix = root.getPath() + File.separator;
        if (!file.getPath().startsWith(prefix) || !file.isFile()
                || !file.getName().endsWith(".zip")) {
            throw new IllegalArgumentException("Only prepared share ZIP files may be shared.");
        }
        String relative = file.getPath().substring(prefix.length());
        Uri.Builder uri = new Uri.Builder().scheme("content")
                .authority(context.getPackageName() + ".archive-share");
        for (String segment : relative.split("/")) uri.appendPath(segment);
        return uri.build();
    }

    private File resolve(Uri uri) throws FileNotFoundException {
        try {
            Context context = getContext();
            if (context == null || !"content".equals(uri.getScheme())
                    || !(context.getPackageName() + ".archive-share").equals(uri.getAuthority())) {
                throw new FileNotFoundException("Invalid share URI.");
            }
            List<String> parts = uri.getPathSegments();
            if (parts.size() != 2 || !parts.get(0).startsWith("share-")
                    || parts.get(0).contains("..") || parts.get(1).contains("/")) {
                throw new FileNotFoundException("Invalid share path.");
            }
            File root = new File(context.getFilesDir(), "archive_shares").getCanonicalFile();
            File file = new File(new File(root, parts.get(0)), parts.get(1)).getCanonicalFile();
            if (!uriFor(context, file.getPath()).equals(uri)) {
                throw new FileNotFoundException("Invalid share path.");
            }
            return file;
        } catch (IOException | IllegalArgumentException error) {
            throw new FileNotFoundException("Share ZIP is unavailable.");
        }
    }

    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri uri) { return "application/zip"; }

    @Override public Cursor query(Uri uri, String[] projection, String selection,
            String[] args, String sortOrder) {
        try {
            File file = resolve(uri);
            String[] columns = projection == null
                    ? new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE} : projection;
            MatrixCursor cursor = new MatrixCursor(columns);
            Object[] values = new Object[columns.length];
            for (int index = 0; index < columns.length; index++) {
                if (OpenableColumns.DISPLAY_NAME.equals(columns[index])) values[index] = file.getName();
                if (OpenableColumns.SIZE.equals(columns[index])) values[index] = file.length();
            }
            cursor.addRow(values);
            return cursor;
        } catch (FileNotFoundException error) {
            return null;
        }
    }

    @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("Share ZIP is read-only.");
        return ParcelFileDescriptor.open(resolve(uri), ParcelFileDescriptor.MODE_READ_ONLY);
    }

    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String where, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String where, String[] args) { throw new UnsupportedOperationException(); }
}
